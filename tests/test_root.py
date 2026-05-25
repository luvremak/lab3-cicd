"""Tests for the root / endpoint (HTML only)."""

from fastapi.testclient import TestClient


def test_root_returns_html_when_accept_html(client: TestClient) -> None:
    r = client.get("/", headers={"Accept": "text/html"})
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "mywebapp" in r.text


def test_root_returns_html_when_no_accept(client: TestClient) -> None:
    # No Accept header → server may default to HTML for the root.
    r = client.get("/")
    assert r.status_code == 200


def test_root_406_for_json_only(client: TestClient) -> None:
    r = client.get("/", headers={"Accept": "application/json"})
    assert r.status_code == 406  # root is HTML only
