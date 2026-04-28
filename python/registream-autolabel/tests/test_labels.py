"""Unit tests for registream.autolabel._labels."""

from __future__ import annotations

import pandas as pd
import pytest

from registream.autolabel._labels import (
    ATTRS_KEY,
    apply_labels,
    apply_value_labels,
    apply_variable_labels,
    ensure_attrs_initialized,
    get_value_labels,
    get_variable_labels,
    parse_value_labels_stata,
)


# ─── Helpers: synthetic metadata builders ─────────────────────────────────────


def _v1_variables_metadata() -> pd.DataFrame:
    """Build a minimal v1 variables metadata DataFrame."""
    return pd.DataFrame(
        {
            "variable_name": ["age", "sex", "income"],
            "variable_label": ["Age in years", "Biological sex", "Annual income"],
            "variable_definition": ["Age", "Sex", "Income"],
            "variable_unit": ["years", "", "SEK"],
            "variable_type": ["continuous", "categorical", "continuous"],
            "value_label_id": ["", "sex_lbl", ""],
        }
    )


def _values_metadata() -> pd.DataFrame:
    """Build a minimal value-labels metadata DataFrame."""
    return pd.DataFrame(
        {
            "value_label_id": ["sex_lbl", "color_lbl"],
            "variable_name": ["sex", "color"],
            "value_labels_stata": [
                '"1" "Male" "2" "Female"',
                '"R" "Red" "G" "Green" "B" "Blue"',
            ],
        }
    )


# ─── parse_value_labels_stata: empty / None / NaN ─────────────────────────────


def test_parse_value_labels_empty_string() -> None:
    assert parse_value_labels_stata("") == {}


def test_parse_value_labels_whitespace_only() -> None:
    assert parse_value_labels_stata("   ") == {}


def test_parse_value_labels_none() -> None:
    assert parse_value_labels_stata(None) == {}


def test_parse_value_labels_nan() -> None:
    assert parse_value_labels_stata(float("nan")) == {}


# ─── parse_value_labels_stata: happy path ────────────────────────────────────


def test_parse_value_labels_single_quoted_pair() -> None:
    assert parse_value_labels_stata('"1" "Male"') == {1: "Male"}


def test_parse_value_labels_multiple_pairs() -> None:
    assert parse_value_labels_stata('"1" "Male" "2" "Female"') == {1: "Male", 2: "Female"}


def test_parse_value_labels_negative_code() -> None:
    assert parse_value_labels_stata('"-99" "Missing"') == {-99: "Missing"}


def test_parse_value_labels_string_code() -> None:
    """Codes that don't parse as integers are kept as strings."""
    assert parse_value_labels_stata('"K" "Kvinna" "M" "Man"') == {"K": "Kvinna", "M": "Man"}


def test_parse_value_labels_mixed_string_and_numeric_codes() -> None:
    """Real example from autolabel.ado line 505: kon metadata mixes both."""
    result = parse_value_labels_stata(
        '"K" "Woman" "M" "Man" "1" "Man" "2" "Woman"'
    )
    assert result == {"K": "Woman", "M": "Man", 1: "Man", 2: "Woman"}


def test_parse_value_labels_multi_word_label() -> None:
    """Quoted labels can contain spaces."""
    assert parse_value_labels_stata('"1" "Married with children"') == {
        1: "Married with children"
    }


def test_parse_value_labels_unquoted_codes_and_labels() -> None:
    """Unquoted bare tokens are also accepted (fallback robustness)."""
    assert parse_value_labels_stata("1 yes 2 no") == {1: "yes", 2: "no"}


def test_parse_value_labels_mixed_quoted_unquoted() -> None:
    """Some pairs quoted, others not; should parse all of them."""
    result = parse_value_labels_stata('1 "Yes please" 2 No')
    assert result == {1: "Yes please", 2: "No"}


# ─── parse_value_labels_stata: escaped quotes ────────────────────────────────


def test_parse_value_labels_escaped_quote_in_label() -> None:
    """Stata uses `""` as the escape for an embedded `"`."""
    result = parse_value_labels_stata('"1" "Don""t know"')
    assert result == {1: 'Don"t know'}


def test_parse_value_labels_multiple_escaped_quotes() -> None:
    result = parse_value_labels_stata('"1" "She said ""hi"""')
    assert result == {1: 'She said "hi"'}


# ─── parse_value_labels_stata: edge cases ────────────────────────────────────


def test_parse_value_labels_odd_token_dropped() -> None:
    """A trailing unpaired token is silently dropped (matches Stata's
    `forval k = 1(2)nwords` loop which only iterates complete pairs)."""
    assert parse_value_labels_stata('"1" "Male" "2"') == {1: "Male"}


def test_parse_value_labels_extra_whitespace() -> None:
    assert parse_value_labels_stata('  "1"   "Male"   "2"   "Female"  ') == {
        1: "Male",
        2: "Female",
    }


def test_parse_value_labels_returns_int_keys_when_possible() -> None:
    result = parse_value_labels_stata('"1" "A" "2" "B"')
    assert isinstance(list(result.keys())[0], int)


# ─── ensure_attrs_initialized ─────────────────────────────────────────────────


def test_ensure_attrs_initialized_fresh_df() -> None:
    df = pd.DataFrame({"x": [1, 2, 3]})
    ensure_attrs_initialized(df)
    assert ATTRS_KEY in df.attrs
    assert df.attrs[ATTRS_KEY] == {"variable_labels": {}, "value_labels": {}}


def test_ensure_attrs_initialized_idempotent() -> None:
    df = pd.DataFrame({"x": [1]})
    ensure_attrs_initialized(df)
    df.attrs[ATTRS_KEY]["variable_labels"]["x"] = "X label"
    ensure_attrs_initialized(df)
    assert df.attrs[ATTRS_KEY]["variable_labels"]["x"] == "X label"


def test_ensure_attrs_initialized_partial_attrs() -> None:
    """If df.attrs[ATTRS_KEY] exists but is missing one of the subdicts,
    only the missing one is added."""
    df = pd.DataFrame({"x": [1]})
    df.attrs[ATTRS_KEY] = {"variable_labels": {"x": "X"}}  # value_labels missing
    ensure_attrs_initialized(df)
    assert "variable_labels" in df.attrs[ATTRS_KEY]
    assert "value_labels" in df.attrs[ATTRS_KEY]
    assert df.attrs[ATTRS_KEY]["variable_labels"]["x"] == "X"  # not clobbered


# ─── apply_variable_labels ────────────────────────────────────────────────────


def test_apply_variable_labels_basic() -> None:
    df = pd.DataFrame({"age": [30, 40], "sex": [1, 2], "income": [100, 200]})
    metadata = _v1_variables_metadata()

    count = apply_variable_labels(df, metadata)

    assert count == 3
    assert df.attrs[ATTRS_KEY]["variable_labels"]["age"] == "Age in years (years)"
    assert df.attrs[ATTRS_KEY]["variable_labels"]["sex"] == "Biological sex"
    assert df.attrs[ATTRS_KEY]["variable_labels"]["income"] == "Annual income (SEK)"


def test_apply_variable_labels_unit_skipped_when_empty() -> None:
    """A row with empty `variable_unit` should NOT have a unit suffix."""
    df = pd.DataFrame({"sex": [1, 2]})
    metadata = _v1_variables_metadata()

    apply_variable_labels(df, metadata)
    assert df.attrs[ATTRS_KEY]["variable_labels"]["sex"] == "Biological sex"
    assert "(" not in df.attrs[ATTRS_KEY]["variable_labels"]["sex"]


def test_apply_variable_labels_include_unit_false() -> None:
    """include_unit=False suppresses the unit suffix entirely."""
    df = pd.DataFrame({"age": [30]})
    metadata = _v1_variables_metadata()

    apply_variable_labels(df, metadata, include_unit=False)
    assert df.attrs[ATTRS_KEY]["variable_labels"]["age"] == "Age in years"


def test_apply_variable_labels_case_insensitive_match() -> None:
    """`Age` in the user's df should match `age` in metadata."""
    df = pd.DataFrame({"Age": [30], "SEX": [1]})
    metadata = _v1_variables_metadata()

    apply_variable_labels(df, metadata)
    # Stored under the user's original column name (Case preserved)
    assert "Age" in df.attrs[ATTRS_KEY]["variable_labels"]
    assert "SEX" in df.attrs[ATTRS_KEY]["variable_labels"]
    assert "age" not in df.attrs[ATTRS_KEY]["variable_labels"]


def test_apply_variable_labels_no_metadata_columns() -> None:
    """Empty metadata DataFrame → 0 labels applied."""
    df = pd.DataFrame({"age": [30]})
    empty = pd.DataFrame()
    assert apply_variable_labels(df, empty) == 0


def test_apply_variable_labels_no_matching_columns() -> None:
    """Metadata with no rows matching df columns → 0 applied."""
    df = pd.DataFrame({"unrelated": [1]})
    metadata = _v1_variables_metadata()
    assert apply_variable_labels(df, metadata) == 0


def test_apply_variable_labels_variables_restriction() -> None:
    """`variables=[...]` restricts which columns get labeled."""
    df = pd.DataFrame({"age": [30], "sex": [1], "income": [100]})
    metadata = _v1_variables_metadata()

    count = apply_variable_labels(df, metadata, variables=["age"])
    assert count == 1
    assert "age" in df.attrs[ATTRS_KEY]["variable_labels"]
    assert "sex" not in df.attrs[ATTRS_KEY]["variable_labels"]


def test_apply_variable_labels_skip_nan_label() -> None:
    df = pd.DataFrame({"age": [30]})
    metadata = pd.DataFrame(
        {
            "variable_name": ["age"],
            "variable_label": [None],
        }
    )
    assert apply_variable_labels(df, metadata) == 0


def test_apply_variable_labels_skip_empty_label() -> None:
    df = pd.DataFrame({"age": [30]})
    metadata = pd.DataFrame(
        {
            "variable_name": ["age"],
            "variable_label": ["   "],  # whitespace only
        }
    )
    assert apply_variable_labels(df, metadata) == 0


# ─── apply_value_labels ──────────────────────────────────────────────────────


def test_apply_value_labels_basic() -> None:
    df = pd.DataFrame({"sex": [1, 2]})
    var_meta = _v1_variables_metadata()
    val_meta = _values_metadata()

    count = apply_value_labels(df, var_meta, val_meta)

    assert count == 1
    assert df.attrs[ATTRS_KEY]["value_labels"]["sex"] == {1: "Male", 2: "Female"}


def test_apply_value_labels_no_value_label_id_skipped() -> None:
    """Variables without a value_label_id are silently skipped (e.g., continuous)."""
    df = pd.DataFrame({"age": [30, 40]})  # age has empty value_label_id
    var_meta = _v1_variables_metadata()
    val_meta = _values_metadata()

    count = apply_value_labels(df, var_meta, val_meta)
    assert count == 0
    assert "age" not in df.attrs[ATTRS_KEY]["value_labels"]


def test_apply_value_labels_string_codes() -> None:
    df = pd.DataFrame({"color": ["R", "G", "B"]})
    var_meta = pd.DataFrame(
        {
            "variable_name": ["color"],
            "variable_label": ["Color"],
            "value_label_id": ["color_lbl"],
        }
    )
    val_meta = _values_metadata()

    apply_value_labels(df, var_meta, val_meta)
    assert df.attrs[ATTRS_KEY]["value_labels"]["color"] == {
        "R": "Red",
        "G": "Green",
        "B": "Blue",
    }


def test_apply_value_labels_returned_dict_is_independent_copy() -> None:
    """Mutating the per-variable dict via df.attrs should NOT affect future
    apply_value_labels calls (the parser cache is private)."""
    df1 = pd.DataFrame({"sex": [1, 2]})
    var_meta = _v1_variables_metadata()
    val_meta = _values_metadata()

    apply_value_labels(df1, var_meta, val_meta)
    df1.attrs[ATTRS_KEY]["value_labels"]["sex"][3] = "Other"

    df2 = pd.DataFrame({"sex": [1, 2]})
    apply_value_labels(df2, var_meta, val_meta)
    assert 3 not in df2.attrs[ATTRS_KEY]["value_labels"]["sex"]


def test_apply_value_labels_no_value_metadata_columns() -> None:
    """If value_labels metadata is missing required columns → 0 applied."""
    df = pd.DataFrame({"sex": [1]})
    var_meta = _v1_variables_metadata()
    bad_val_meta = pd.DataFrame({"foo": ["bar"]})
    assert apply_value_labels(df, var_meta, bad_val_meta) == 0


# ─── apply_labels (orchestrator) ─────────────────────────────────────────────


def test_apply_labels_both() -> None:
    df = pd.DataFrame({"age": [30, 40], "sex": [1, 2]})
    var_count, val_count = apply_labels(
        df, _v1_variables_metadata(), _values_metadata(), label_type="both"
    )
    assert var_count == 2  # age + sex
    assert val_count == 1  # only sex has value_label_id


def test_apply_labels_variables_only() -> None:
    df = pd.DataFrame({"age": [30, 40], "sex": [1, 2]})
    var_count, val_count = apply_labels(
        df, _v1_variables_metadata(), label_type="variables"
    )
    assert var_count == 2
    assert val_count == 0
    assert df.attrs[ATTRS_KEY]["value_labels"] == {}


def test_apply_labels_values_only() -> None:
    df = pd.DataFrame({"sex": [1, 2]})
    var_count, val_count = apply_labels(
        df, _v1_variables_metadata(), _values_metadata(), label_type="values"
    )
    assert var_count == 0
    assert val_count == 1


def test_apply_labels_values_without_values_metadata_raises() -> None:
    df = pd.DataFrame({"sex": [1, 2]})
    with pytest.raises(ValueError, match="requires `values_metadata`"):
        apply_labels(df, _v1_variables_metadata(), label_type="values")


def test_apply_labels_both_without_values_metadata_raises() -> None:
    df = pd.DataFrame({"sex": [1, 2]})
    with pytest.raises(ValueError, match="requires `values_metadata`"):
        apply_labels(df, _v1_variables_metadata(), label_type="both")


# ─── get_variable_labels / get_value_labels (read accessors) ─────────────────


def test_get_variable_labels_empty_df() -> None:
    df = pd.DataFrame({"x": [1]})
    assert get_variable_labels(df) == {}


def test_get_variable_labels_returns_copy() -> None:
    """Mutating the returned dict must not affect df.attrs."""
    df = pd.DataFrame({"age": [30]})
    apply_variable_labels(df, _v1_variables_metadata())

    labels = get_variable_labels(df)
    labels["age"] = "MODIFIED"
    assert df.attrs[ATTRS_KEY]["variable_labels"]["age"] != "MODIFIED"


def test_get_value_labels_empty_df() -> None:
    df = pd.DataFrame({"x": [1]})
    assert get_value_labels(df) == {}


def test_get_value_labels_returns_two_level_copy() -> None:
    """Mutating the returned per-variable dict must not affect df.attrs."""
    df = pd.DataFrame({"sex": [1, 2]})
    apply_value_labels(df, _v1_variables_metadata(), _values_metadata())

    labels = get_value_labels(df)
    labels["sex"][1] = "MODIFIED"
    assert df.attrs[ATTRS_KEY]["value_labels"]["sex"][1] == "Male"


def test_get_variable_labels_after_apply() -> None:
    df = pd.DataFrame({"age": [30], "sex": [1]})
    apply_variable_labels(df, _v1_variables_metadata())

    labels = get_variable_labels(df)
    assert labels == {"age": "Age in years (years)", "sex": "Biological sex"}


# ─── df.attrs storage convention ─────────────────────────────────────────────


def test_attrs_key_is_registream_not_legacy_registream_labels() -> None:
    """Per `08_PYTHON_ECOSYSTEM.md` "Label storage in df.attrs", the
    namespace key is "registream", NOT the legacy "registream_labels"."""
    df = pd.DataFrame({"age": [30]})
    apply_variable_labels(df, _v1_variables_metadata())
    assert "registream" in df.attrs
    assert "registream_labels" not in df.attrs  # legacy key must NOT be set
