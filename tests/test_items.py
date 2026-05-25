"""Tests for the business endpoints: /items, /items/{id}."""

from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# POST /items — create
# ---------------------------------------------------------------------------


def test_post_items_creates_and_returns_201_json(client: TestClient) -> None:
    r = client.post(
        "/items",
        json={"name": "Drill", "quantity": 5},
        headers={"Accept": "application/json"},
    )
    assert r.status_code == 201
    body = r.json()
    assert body["name"] == "Drill"
    assert body["quantity"] == 5
    assert body["id"] >= 1


def test_post_items_rejects_empty_name(client: TestClient) -> None:
    r = client.post("/items", json={"name": "", "quantity": 5})
    assert r.status_code == 422


def test_post_items_rejects_negative_quantity(client: TestClient) -> None:
    r = client.post("/items", json={"name": "Hammer", "quantity": -1})
    assert r.status_code == 422


def test_post_items_rejects_missing_fields(client: TestClient) -> None:
    r = client.post("/items", json={"name": "Hammer"})
    assert r.status_code == 422


# ---------------------------------------------------------------------------
# GET /items — list
# ---------------------------------------------------------------------------


def test_get_items_empty_returns_empty_list(client: TestClient) -> None:
    r = client.get("/items")
    assert r.status_code == 200
    assert r.json() == []


def test_get_items_lists_created_items(client: TestClient) -> None:
    client.post("/items", json={"name": "Drill",  "quantity": 5})
    client.post("/items", json={"name": "Hammer", "quantity": 2})

    r = client.get("/items")
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 2
    # list endpoint returns only id+name (not quantity/created_at)
    assert {it["name"] for it in items} == {"Drill", "Hammer"}
    assert all("id" in it for it in items)


def test_get_items_html_when_accept_html(client: TestClient) -> None:
    client.post("/items", json={"name": "Drill", "quantity": 5})

    r = client.get("/items", headers={"Accept": "text/html"})
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "Drill" in r.text


# ---------------------------------------------------------------------------
# GET /items/{id} — show one
# ---------------------------------------------------------------------------


def test_get_item_by_id_returns_full_details(client: TestClient) -> None:
    created = client.post("/items", json={"name": "Drill", "quantity": 5}).json()
    item_id = created["id"]

    r = client.get(f"/items/{item_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["id"] == item_id
    assert body["name"] == "Drill"
    assert body["quantity"] == 5
    assert "created_at" in body  # full details include the timestamp


def test_get_item_by_id_404_for_missing(client: TestClient) -> None:
    r = client.get("/items/99999")
    assert r.status_code == 404


def test_get_item_by_id_html(client: TestClient) -> None:
    created = client.post("/items", json={"name": "Drill", "quantity": 5}).json()
    r = client.get(f"/items/{created['id']}", headers={"Accept": "text/html"})
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
