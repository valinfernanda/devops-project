"""Integration tests: the real API talking to a real PostgreSQL database.

They need APP_DATABASE_URL pointing at a migrated database. Run them with Docker Compose:
    docker compose run --rm tests
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from taskapi.db import engine
from taskapi.main import app

pytestmark = pytest.mark.integration
client = TestClient(app)


@pytest.fixture(autouse=True)
def clean_tasks_table():
    """Start every test with an empty table, so tests don't affect each other."""
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE tasks RESTART IDENTITY"))
    yield


def test_ready_with_real_database():
    assert client.get("/ready").status_code == 200


def test_task_lifecycle():
    # Create
    created = client.post("/tasks", json={"title": "Learn Docker"})
    assert created.status_code == 201
    task = created.json()
    assert task["title"] == "Learn Docker"
    assert task["done"] is False

    # Read
    assert client.get(f"/tasks/{task['id']}").json()["title"] == "Learn Docker"
    assert len(client.get("/tasks").json()) == 1

    # Update
    updated = client.patch(f"/tasks/{task['id']}", json={"done": True})
    assert updated.status_code == 200
    assert updated.json()["done"] is True

    # Delete
    assert client.delete(f"/tasks/{task['id']}").status_code == 204
    assert client.get(f"/tasks/{task['id']}").status_code == 404


def test_search_is_case_insensitive():
    for title in ["Learn Docker", "Learn Kubernetes", "Buy milk"]:
        client.post("/tasks", json={"title": title})
    response = client.get("/tasks/search", params={"q": "learn"})
    assert response.status_code == 200
    assert [t["title"] for t in response.json()] == ["Learn Docker", "Learn Kubernetes"]


def test_search_is_not_vulnerable_to_sql_injection():
    # Regression test for the SQL injection caught in PR #2.
    client.post("/tasks", json={"title": "Learn Docker"})

    # With string-built SQL this returned EVERY row. It must match nothing.
    attack = client.get("/tasks/search", params={"q": "nomatch' OR '1'='1' --"})
    assert attack.status_code == 200
    assert attack.json() == []

    # A destructive payload must be treated as plain text, and the table must survive.
    assert client.get("/tasks/search", params={"q": "'; DROP TABLE tasks; --"}).status_code == 200
    assert len(client.get("/tasks").json()) == 1


def test_search_treats_wildcards_literally():
    client.post("/tasks", json={"title": "100% done"})
    client.post("/tasks", json={"title": "Learn Docker"})
    assert [t["title"] for t in client.get("/tasks/search", params={"q": "%"}).json()] == [
        "100% done"
    ]


def test_missing_task_returns_404():
    assert client.get("/tasks/999").status_code == 404
    assert client.patch("/tasks/999", json={"done": True}).status_code == 404
    assert client.delete("/tasks/999").status_code == 404
