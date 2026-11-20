"""Unit tests: fast, no database, no network. They test one piece of logic in isolation."""

from fastapi.testclient import TestClient

from taskapi import main

client = TestClient(main.app)


def test_health_is_ok_without_database():
    # Liveness must NOT depend on the database: a DB outage should not restart the app.
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_ready_returns_503_when_database_is_down(monkeypatch):
    # "monkeypatch" replaces check_database with a fake that simulates a DB outage.
    monkeypatch.setattr(main, "check_database", lambda: False)
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["status"] == "not ready"


def test_ready_returns_200_when_database_is_up(monkeypatch):
    monkeypatch.setattr(main, "check_database", lambda: True)
    assert client.get("/ready").status_code == 200


def test_create_task_rejects_empty_title():
    # Validation happens in the schema, before any database code runs.
    response = client.post("/tasks", json={"title": ""})
    assert response.status_code == 422


def test_create_task_rejects_too_long_title():
    response = client.post("/tasks", json={"title": "x" * 201})
    assert response.status_code == 422
