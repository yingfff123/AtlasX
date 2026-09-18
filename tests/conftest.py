"""Test env must be set before radar.config.Settings loads."""

from __future__ import annotations

import os

from cryptography.fernet import Fernet

os.environ.setdefault("RADAR_MASTER_KEY", Fernet.generate_key().decode())
# Import-time create_engine is lazy; do not use SQLite (pool_size args are PG-only).
os.environ.setdefault(
    "RADAR_DATABASE_URL",
    "postgresql+psycopg://radar:radar@127.0.0.1:1/radar",
)
os.environ.setdefault("RADAR_ALLOW_INSECURE_DB", "1")
os.environ.setdefault("RADAR_SKIP_RESET_ZOMBIE", "1")
os.environ.setdefault("RADAR_HTTPS_ONLY", "0")

import pytest

from radar.auth.rbac import invalidate_users_exist_cache


@pytest.fixture(autouse=True)
def _reset_users_exist_cache():
    invalidate_users_exist_cache()
    yield
    invalidate_users_exist_cache()
