"""AX-SEC-11: users_exist 负缓存 + 无用户不可匿名 can_write。"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from radar.auth.rbac import (
    TOKEN_ADMIN,
    invalidate_users_exist_cache,
    users_exist,
)


class _Scalar:
    def __init__(self, n):
        self._n = n

    def scalar(self):
        return self._n


class _CountingSession:
    def __init__(self, counts: list[int | Exception]):
        self._counts = list(counts)
        self.calls = 0

    def execute(self, *_a, **_k):
        self.calls += 1
        val = self._counts.pop(0)
        if isinstance(val, Exception):
            raise val
        return _Scalar(val)


def test_users_exist_does_not_cache_false():
    session = _CountingSession([0, 1])
    assert users_exist(session) is False
    assert users_exist(session) is True
    assert session.calls == 2


def test_users_exist_caches_true_until_invalidate():
    session = _CountingSession([1, 0])
    assert users_exist(session) is True
    assert users_exist(session) is True
    assert session.calls == 1
    invalidate_users_exist_cache()
    assert users_exist(session) is False
    assert session.calls == 2


def test_users_exist_db_failure_raises():
    session = _CountingSession([RuntimeError("pg down")])
    with pytest.raises(RuntimeError, match="pg down"):
        users_exist(session)


def _probe_client():
    """Minimal app + AtlasX auth middleware; no Web lifespan."""
    from radar.server.app import _AuthMiddleware

    probe = FastAPI()

    @probe.get("/api/probe")
    def _probe(request: Request):
        user = getattr(request.state, "user", None)
        return {
            "can_write": bool(getattr(request.state, "can_write", False)),
            "username": getattr(user, "username", None),
            "is_token_admin": user is TOKEN_ADMIN,
        }

    @probe.post("/api/probe-write")
    def _write(request: Request):
        return {"can_write": bool(getattr(request.state, "can_write", False))}

    @probe.get("/overview-html")
    def _html(request: Request):
        return {"can_write": bool(getattr(request.state, "can_write", False))}

    probe.add_middleware(_AuthMiddleware)
    return TestClient(probe)


def test_no_users_anonymous_does_not_get_can_write():
    with (
        patch("radar.auth.rbac.users_exist", return_value=False),
        patch("radar.server.app._access_token_ok", return_value=None),
    ):
        client = _probe_client()
        r = client.get("/api/probe", headers={"Accept": "application/json"})
    assert r.status_code == 401
    assert r.json()["detail"] == "unauthorized"


def test_no_users_html_redirects_to_login_not_open_write():
    with (
        patch("radar.auth.rbac.users_exist", return_value=False),
        patch("radar.server.app._access_token_ok", return_value=None),
    ):
        client = _probe_client()
        r = client.get(
            "/overview-html", headers={"Accept": "text/html"}, follow_redirects=False
        )
    assert r.status_code == 303
    assert "/login" in r.headers.get("location", "")


def test_no_users_access_token_is_token_admin_can_write():
    with (
        patch("radar.auth.rbac.users_exist", return_value=False),
        patch("radar.server.app._access_token_ok", return_value=True),
    ):
        client = _probe_client()
        r = client.get("/api/probe")
    assert r.status_code == 200
    body = r.json()
    assert body["can_write"] is True
    assert body["is_token_admin"] is True
    assert body["username"] == "__token__"


def test_no_users_wrong_access_token_unauthorized():
    with (
        patch("radar.auth.rbac.users_exist", return_value=False),
        patch("radar.server.app._access_token_ok", return_value=False),
    ):
        client = _probe_client()
        r = client.get("/api/probe")
    assert r.status_code == 401


def test_users_exist_db_failure_is_503():
    with patch("radar.auth.rbac.users_exist", side_effect=RuntimeError("pg down")):
        client = _probe_client()
        r = client.get("/api/probe")
    assert r.status_code == 503
    assert r.json()["detail"] == "auth_unavailable"
