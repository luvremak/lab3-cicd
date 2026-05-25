"""Common pytest fixtures.

The test suite runs against a real PostgreSQL instance (in CI it's the
`postgres` service of GitHub Actions; locally — `docker compose up db`).
A throwaway config TOML is written for each test session pointing at that
DB; the application's normal lifespan does the rest.
"""

from __future__ import annotations

import os
import tempfile
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

import app.db as db_module


@pytest.fixture(scope="session")
def config_file() -> Iterator[str]:
    """Write a temporary TOML config pointing at the test database."""
    host = os.environ.get("MYWEBAPP_TEST_DB_HOST", "127.0.0.1")
    port = int(os.environ.get("MYWEBAPP_TEST_DB_PORT", "5432"))
    name = os.environ.get("MYWEBAPP_TEST_DB_NAME", "mywebapp")
    user = os.environ.get("MYWEBAPP_TEST_DB_USER", "mywebapp")
    pwd  = os.environ.get("MYWEBAPP_TEST_DB_PASSWORD", "testpass")

    content = f"""
[server]
host = "127.0.0.1"
port = 5200

[database]
host = "{host}"
port = {port}
name = "{name}"
user = "{user}"
password = "{pwd}"
"""
    with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as fh:
        fh.write(content)
        path = fh.name

    os.environ["MYWEBAPP_CONFIG"] = path
    yield path
    os.unlink(path)


@pytest.fixture(scope="session")
def _migrate(config_file: str) -> None:
    """Apply schema migrations once per test session."""
    # Import lazily so MYWEBAPP_CONFIG is already in place.
    from app.migrate import main as migrate_main
    migrate_main()


@pytest.fixture
def client(config_file: str, _migrate: None) -> Iterator[TestClient]:
    """A FastAPI TestClient with the lifespan run (DB pool initialised)."""
    # Import lazily so MYWEBAPP_CONFIG is already in place.
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _truncate_items(client: TestClient) -> Iterator[None]:
    """Start every test with an empty items table.

    Runs AFTER `client` (so the pool exists) and BEFORE the test body.
    """
    pool = db_module.get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("TRUNCATE TABLE items RESTART IDENTITY")
        conn.commit()
    yield
