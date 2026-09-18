"""Fail-closed Web lifespan: ensure_ready + assert_not_open_mode must not be swallowed."""

from __future__ import annotations

import asyncio
from contextlib import contextmanager
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def _fake_session_cm():
    @contextmanager
    def _cm():
        s = MagicMock()
        s.get.return_value = None
        yield s

    return _cm()


def _lifespan_patches(**overrides):
    """Patch DB-touching startup so tests can exercise lifespan without PG."""
    mapping = {
        "radar.server.app.ensure_ready": MagicMock(name="ensure_ready"),
        "radar.server.app.dispose_engine": MagicMock(name="dispose_engine"),
        "radar.server.app.kill_zombie_scans": MagicMock(return_value=0),
        "radar.server.app.get_session": MagicMock(side_effect=_fake_session_cm),
        "radar.llm.base.configure_from_session": MagicMock(),
        "radar.server.proxy.apply_from_session": MagicMock(),
        "radar.auth.bootstrap.ensure_default_admin": MagicMock(return_value=False),
        "radar.auth.bootstrap.backfill_must_change_for_default_password": MagicMock(
            return_value=0
        ),
        "radar.auth.bootstrap.assert_not_open_mode": MagicMock(),
        "radar.logging_setup.quiet_http_loggers": MagicMock(),
        "radar.sys_log.install_runtime_handler": MagicMock(),
    }
    mapping.update(overrides)
    return mapping


@contextmanager
def patched_lifespan(**overrides):
    mapping = _lifespan_patches(**overrides)
    cms = [patch(target, new=value) for target, value in mapping.items()]
    started = []
    try:
        for cm in cms:
            started.append(cm)
            cm.__enter__()
        yield mapping
    finally:
        for cm in reversed(started):
            cm.__exit__(None, None, None)


async def _enter_lifespan(app, lifespan_fn):
    async with lifespan_fn(app):
        return "served"


def _assert_lifespan_aborts(app, lifespan_fn, *, match: str) -> None:
    """SystemExit from hard gates must surface; TestClient must not yield a server."""
    served_direct = False
    with pytest.raises(SystemExit, match=match):
        result = asyncio.run(_enter_lifespan(app, lifespan_fn))
        served_direct = result == "served"
    assert served_direct is False

    served_client = False
    with pytest.raises(BaseException):
        with TestClient(app) as client:
            served_client = True
            client.get("/healthz")
    assert served_client is False


def test_lifespan_invokes_ensure_ready():
    from radar.server.app import app

    ready = MagicMock(name="ensure_ready")
    with patched_lifespan(**{"radar.server.app.ensure_ready": ready}):
        with TestClient(app) as client:
            client.get("/healthz")
    assert ready.call_count >= 1


def test_lifespan_aborts_when_ensure_ready_exits():
    from radar.server.app import app, lifespan

    ready = MagicMock(side_effect=SystemExit("无法连接 PostgreSQL"))
    with patched_lifespan(**{"radar.server.app.ensure_ready": ready}):
        _assert_lifespan_aborts(app, lifespan, match="PostgreSQL")
    assert ready.call_count >= 1


def test_lifespan_aborts_when_assert_not_open_mode_exits():
    from radar.server.app import app, lifespan

    gate = MagicMock(side_effect=SystemExit("拒绝开放模式"))
    with patched_lifespan(**{"radar.auth.bootstrap.assert_not_open_mode": gate}):
        _assert_lifespan_aborts(app, lifespan, match="开放模式")
    assert gate.call_count >= 1


def test_assert_not_open_mode_not_swallowed_when_bootstrap_fails():
    """Regression: ensure_default_admin 普通异常不得跳过开放模式硬门。"""
    from radar.server.app import app, lifespan

    boot = MagicMock(side_effect=RuntimeError("app_user 表未迁移"))
    gate = MagicMock(side_effect=SystemExit("拒绝开放模式"))
    with patched_lifespan(
        **{
            "radar.auth.bootstrap.ensure_default_admin": boot,
            "radar.auth.bootstrap.assert_not_open_mode": gate,
        }
    ):
        _assert_lifespan_aborts(app, lifespan, match="开放模式")
    assert boot.call_count >= 1
    assert gate.call_count >= 1


def test_assert_not_open_mode_not_swallowed_when_soft_cleanup_fails():
    from radar.server.app import app, lifespan

    gate = MagicMock(side_effect=SystemExit("拒绝开放模式"))
    with patched_lifespan(
        **{
            "radar.server.app.kill_zombie_scans": MagicMock(
                side_effect=RuntimeError("pg_stat_activity 不可用")
            ),
            "radar.auth.bootstrap.assert_not_open_mode": gate,
        }
    ):
        _assert_lifespan_aborts(app, lifespan, match="开放模式")
    assert gate.call_count >= 1


def test_ensure_ready_runs_before_soft_cleanup():
    from radar.server.app import app

    order: list[str] = []

    def ready():
        order.append("ensure_ready")

    def zombies():
        order.append("zombie")
        return 0

    def boot():
        order.append("bootstrap")
        return False

    def gate():
        order.append("assert_not_open_mode")

    with patched_lifespan(
        **{
            "radar.server.app.ensure_ready": MagicMock(side_effect=ready),
            "radar.server.app.kill_zombie_scans": MagicMock(side_effect=zombies),
            "radar.auth.bootstrap.ensure_default_admin": MagicMock(side_effect=boot),
            "radar.auth.bootstrap.assert_not_open_mode": MagicMock(side_effect=gate),
        }
    ):
        with TestClient(app):
            pass
    assert order.index("ensure_ready") < order.index("zombie")
    assert order.index("bootstrap") < order.index("assert_not_open_mode")
    assert order[-1] == "assert_not_open_mode"


def test_soft_systemexit_from_bootstrap_still_aborts():
    from radar.server.app import app, lifespan

    boot = MagicMock(side_effect=SystemExit("bootstrap refused"))
    with patched_lifespan(
        **{"radar.auth.bootstrap.ensure_default_admin": boot}
    ):
        _assert_lifespan_aborts(app, lifespan, match="bootstrap refused")


def test_assert_not_open_mode_empty_db_empty_token_exits(monkeypatch):
    """空库 + 空 TOKEN + SKIP_DEFAULT_ADMIN → 拒启。"""
    monkeypatch.setenv("RADAR_SKIP_DEFAULT_ADMIN", "1")
    monkeypatch.setenv("RADAR_ACCESS_TOKEN", "")
    from radar.auth.bootstrap import assert_not_open_mode
    from radar.config import settings

    monkeypatch.setattr(settings, "access_token", "")
    with patch("radar.auth.rbac.users_exist", return_value=False):
        with pytest.raises(SystemExit, match="拒绝开放模式"):
            assert_not_open_mode()


def test_assert_not_open_mode_allows_access_token_without_users(monkeypatch):
    monkeypatch.setenv("RADAR_ACCESS_TOKEN", "wave1-token")
    from radar.auth.bootstrap import assert_not_open_mode

    with patch("radar.auth.rbac.users_exist", return_value=False):
        assert_not_open_mode()
