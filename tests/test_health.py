"""Tests for the /health/* probes."""

from fastapi.testclient import TestClient


def test_alive_always_returns_200(client: TestClient) -> None:
    r = client.get("/health/alive")
    assert r.status_code == 200


def test_ready_returns_200_when_db_up(client: TestClient) -> None:
    r = client.get("/health/ready")
    assert r.status_code == 200
