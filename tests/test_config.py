"""Unit tests for app.config — no DB, no HTTP."""

import tempfile
from pathlib import Path

import pytest

from app.config import (
    Config,
    DatabaseConfig,
    ServerConfig,
    config_path,
    dsn,
    load_config,
)

VALID_TOML = """
[server]
host = "0.0.0.0"
port = 5200

[database]
host = "db"
port = 5432
name = "mywebapp"
user = "mywebapp"
password = "secret"
"""


def _write_toml(content: str) -> str:
    with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as fh:
        fh.write(content)
        return fh.name


def test_load_config_parses_valid_toml() -> None:
    path = _write_toml(VALID_TOML)
    try:
        cfg = load_config(path)
        assert cfg.server.host == "0.0.0.0"
        assert cfg.server.port == 5200
        assert cfg.database.host == "db"
        assert cfg.database.port == 5432
        assert cfg.database.name == "mywebapp"
    finally:
        Path(path).unlink()


def test_load_config_missing_section_raises() -> None:
    path = _write_toml("[server]\nhost = \"x\"\nport = 1\n")
    try:
        with pytest.raises(KeyError):
            load_config(path)
    finally:
        Path(path).unlink()


def test_load_config_missing_file_raises() -> None:
    with pytest.raises(FileNotFoundError):
        load_config("/nonexistent/path/to/config.toml")


def test_dsn_contains_all_fields() -> None:
    db_conf = DatabaseConfig(
        host="myhost", port=5433, name="mydb", user="u", password="p"
    )
    s = dsn(db_conf)
    assert "host=myhost" in s
    assert "port=5433" in s
    assert "dbname=mydb" in s
    assert "user=u" in s
    assert "password=p" in s
    assert "connect_timeout=" in s


def test_config_path_respects_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MYWEBAPP_CONFIG", "/custom/path.toml")
    assert config_path() == "/custom/path.toml"


def test_config_path_default_when_no_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("MYWEBAPP_CONFIG", raising=False)
    assert config_path() == "/etc/mywebapp/config.toml"


def test_config_dataclasses_immutable() -> None:
    cfg = Config(
        server=ServerConfig(host="h", port=1),
        database=DatabaseConfig(host="h", port=1, name="n", user="u", password="p"),
    )
    # @dataclass(frozen=True) raises FrozenInstanceError on attribute assignment.
    from dataclasses import FrozenInstanceError
    with pytest.raises(FrozenInstanceError):
        cfg.server.host = "x"  # type: ignore[misc]
