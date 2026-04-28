"""Unit tests for the data-fetch layer in registream.autolabel._datasets.

Covers the URL builder, response parser, and error fallbacks of
``_resolve_version``. These tests are what would have caught the
schema_max regression: the autolabel client must pass its required
schema version to the server so the server doesn't fall back to its
default schema_max=1.0 (used for backward compat with old clients).
"""

from __future__ import annotations

from typing import Any

import pytest
import requests

from registream.schema import SCHEMA_VERSION
from registream.autolabel._datasets import _resolve_version


# ── Test doubles ────────────────────────────────────────────────────────────


class _FakeResponse:
    """Minimal stand-in for requests.Response — just enough for
    _resolve_version's parser path."""

    def __init__(self, text: str = "", status_code: int = 200) -> None:
        self.text = text
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}")


def _patch_get(monkeypatch: pytest.MonkeyPatch, response: _FakeResponse) -> dict[str, Any]:
    """Patch requests.get inside _datasets to return a fixed response and
    capture the URL passed to it."""
    captured: dict[str, Any] = {}

    def fake_get(url: str, timeout: float = 0) -> _FakeResponse:
        captured["url"] = url
        captured["timeout"] = timeout
        return response

    monkeypatch.setattr(
        "registream.autolabel._datasets.requests.get",
        fake_get,
    )
    return captured


# ── Regression: URL must include schema_max ─────────────────────────────────


def test_resolve_version_url_includes_schema_max(monkeypatch: pytest.MonkeyPatch) -> None:
    """The info URL MUST pass schema_max so the server returns the latest
    version compatible with this client's parser, not the server's default
    schema_max=1.0 (which exists for old-client backward compat).

    This is the regression test for the bug shipped in 3.0.0: without
    schema_max, the server returned a schema 1.0 bundle and the client's
    schema-v2 parser rejected it with "Schema version mismatch".
    """
    captured = _patch_get(
        monkeypatch,
        _FakeResponse(text="version=20260309\nschema=2.0\nstatus=ok\n"),
    )

    _resolve_version("scb", "eng", "latest")

    assert "url" in captured, "requests.get was not called"
    assert "schema_max=" in captured["url"], (
        f"info URL missing schema_max param: {captured['url']}"
    )
    assert f"schema_max={SCHEMA_VERSION}" in captured["url"], (
        f"info URL must pass the client's SCHEMA_VERSION ({SCHEMA_VERSION}): "
        f"{captured['url']}"
    )


def test_resolve_version_url_targets_correct_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    """The URL must target /api/v1/datasets/<domain>/variables/<lang>/latest/info
    with format=stata. (Different file types or formats would 404 or be parsed wrong.)"""
    captured = _patch_get(
        monkeypatch,
        _FakeResponse(text="version=20260309\nschema=2.0\nstatus=ok\n"),
    )

    _resolve_version("dst", "dan", "latest")

    url = captured["url"]
    assert "/api/v1/datasets/dst/variables/dan/latest/info" in url
    assert "format=stata" in url


# ── Response parsing ────────────────────────────────────────────────────────


def test_resolve_version_parses_version_and_schema(monkeypatch: pytest.MonkeyPatch) -> None:
    """Stata-format key=value response: extract version + schema."""
    _patch_get(
        monkeypatch,
        _FakeResponse(text="version=20260309\nschema=2.0\nstatus=ok\n"),
    )

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "20260309"
    assert schema == "2.0"


def test_resolve_version_handles_missing_schema_line(monkeypatch: pytest.MonkeyPatch) -> None:
    """If the server omits the schema line, fall back to SCHEMA_VERSION
    (defensive — avoid crashing on partial responses)."""
    _patch_get(
        monkeypatch,
        _FakeResponse(text="version=20260309\nstatus=ok\n"),
    )

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "20260309"
    assert schema == SCHEMA_VERSION  # default


def test_resolve_version_handles_missing_version_line(monkeypatch: pytest.MonkeyPatch) -> None:
    """If the server omits the version line, fall back to 'latest'."""
    _patch_get(
        monkeypatch,
        _FakeResponse(text="schema=2.0\nstatus=ok\n"),
    )

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "latest"
    assert schema == "2.0"


def test_resolve_version_ignores_unknown_lines(monkeypatch: pytest.MonkeyPatch) -> None:
    """Future-compatibility: extra response lines are ignored cleanly."""
    _patch_get(
        monkeypatch,
        _FakeResponse(
            text=(
                "version=20260309\n"
                "schema=2.0\n"
                "domain=scb\n"
                "type=variables\n"
                "lang=eng\n"
                "status=ok\n"
                "future_field=xyz\n"
            )
        ),
    )

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "20260309"
    assert schema == "2.0"


# ── Error fallbacks ─────────────────────────────────────────────────────────


def test_resolve_version_falls_back_on_network_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """When the network is unreachable, fall back to ('latest', SCHEMA_VERSION)
    so the caller can fail-soft with the bundled schema version."""

    def fake_get(url: str, timeout: float = 0) -> _FakeResponse:
        raise requests.ConnectionError("network unreachable")

    monkeypatch.setattr(
        "registream.autolabel._datasets.requests.get",
        fake_get,
    )

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "latest"
    assert schema == SCHEMA_VERSION


def test_resolve_version_falls_back_on_http_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """5xx server errors fall back the same way."""
    _patch_get(monkeypatch, _FakeResponse(text="", status_code=503))

    version, schema = _resolve_version("scb", "eng", "latest")

    assert version == "latest"
    assert schema == SCHEMA_VERSION


# ── Explicit version short-circuits ─────────────────────────────────────────


def test_resolve_version_explicit_version_skips_network(monkeypatch: pytest.MonkeyPatch) -> None:
    """When the caller passes a concrete version (not 'latest'), no network
    call is made — the version is returned with the bundled SCHEMA_VERSION."""

    def fake_get(url: str, timeout: float = 0) -> _FakeResponse:
        raise AssertionError(f"network must not be called for explicit version: {url}")

    monkeypatch.setattr(
        "registream.autolabel._datasets.requests.get",
        fake_get,
    )

    version, schema = _resolve_version("scb", "eng", "20260309")

    assert version == "20260309"
    assert schema == SCHEMA_VERSION
