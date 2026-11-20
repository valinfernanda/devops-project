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


def test_missing_task_returns_404():
    assert client.get("/tasks/999").status_code == 404
    assert client.patch("/tasks/999", json={"done": True}).status_code == 404
    assert client.delete("/tasks/999").status_code == 404
