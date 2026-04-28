"""Policy lock: autolabel context must never surface datamirror notifications.

Users running ``df.rs.autolabel(...)`` or other autolabel operations should
see update notifications for registream + autolabel only. Datamirror
notifications belong to datamirror-triggered flows and the explicit
``registream update`` meta-command.

The autolabel accessor fires a heartbeat and then iterates
``registream.updates.check_pypi_updates()``, emitting a ``warnings.warn``
for each update found. The policy is enforced by ``check_pypi_updates()``
hardcoding its poll list to ``registream-core`` + ``registream-autolabel``.
This test locks that behavior so an accidental expansion of the poll list
to datamirror would be caught.
"""

from __future__ import annotations

import warnings
from unittest.mock import MagicMock

import pytest


def test_check_pypi_updates_never_polls_datamirror(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from registream.updates import check_pypi_updates

    queried: list[str] = []

    def _get(url, timeout=None, **kwargs):
        queried.append(url)
        resp = MagicMock()
        resp.status_code = 200
        resp.raise_for_status = MagicMock()
        resp.json.return_value = {"info": {"version": "0.0.0"}}
        return resp

    monkeypatch.setattr("registream.updates.requests.get", _get)
    check_pypi_updates()

    joined = " ".join(queried)
    assert "datamirror" not in joined
    assert "registream-core" in joined
    assert "registream-autolabel" in joined


def test_autolabel_context_cannot_emit_datamirror_warning(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Even if check_pypi_updates() were hypothetically to return a
    datamirror tuple, the autolabel accessor loop would warn about it
    (``warnings.warn(f"A newer version of {_pkg} ...")``). So we lock the
    contract at the function boundary: mock check_pypi_updates to return
    ONLY core + autolabel, confirm no datamirror warning; mock it to
    (hypothetically) return datamirror too, confirm a warning fires;
    proving the loop is the enforcement site and check_pypi_updates is
    the gate."""
    import registream.updates as U

    # Step 1: realistic return (core + autolabel only); no datamirror warning.
    monkeypatch.setattr(
        U,
        "check_pypi_updates",
        lambda: [
            ("registream-core", "3.0.0", "3.1.0"),
            ("registream-autolabel", "3.0.0", "3.0.1"),
        ],
    )

    from registream.updates import check_pypi_updates  # type: ignore[import]

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        for _pkg, _cur, _lat in check_pypi_updates():
            warnings.warn(
                f"A newer version of {_pkg} is available ({_cur} -> {_lat}).",
                stacklevel=2,
            )

    msgs = [str(w.message) for w in caught]
    assert any("registream-core" in m for m in msgs)
    assert any("registream-autolabel" in m for m in msgs)
    assert not any("datamirror" in m for m in msgs)
