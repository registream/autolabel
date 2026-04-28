"""Phase 0 smoke test for registream-autolabel. Real tests land in Phase 2."""


def test_namespace_and_subpackage_import():
    import registream  # noqa: F401
    import registream.autolabel  # noqa: F401

    assert registream.autolabel.__version__ == "3.0.0"
