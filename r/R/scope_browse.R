# scope(): depth-agnostic catalog browser.
#
# Port of `registream-autolabel/src/registream/autolabel/_scope.py`.
# Returns a plain data.frame at every level; callers can chain base R
# / dplyr / gt / whatever. No SMCL / hyperlinks; R-side formatting
# is the caller's responsibility.
#
# Tokens come through `...`, matching Stata's `autolabel scope LISA
# Individer` syntax. A single vector also works: `scope(c("LISA",
# "Individer"))`, because `unlist(list(...))` flattens either shape.
#
# Modes (depth-agnostic, driven by manifest$scope_depth):
#   1. no tokens, no release      → level-1 browse with variable_count
#   2. tokens length K < depth    → level-(K+1) browse under the prefix
#   3. tokens length K == depth   → releases at that scope atom
#   4. tokens + release           → variables at the (scope, release) atom
#   5. overflow rule              → K == depth+1 promotes last token to release

#' @export
scope <- function(...,
                  domain    = "scb",
                  lang      = "eng",
                  search    = NULL,
                  release   = NULL,
                  directory = NULL) {
  log_and_heartbeat("scope")

  tokens <- unlist(list(...), use.names = FALSE)
  tokens <- tokens[!is.na(tokens) & nzchar(tokens)]

  bundle <- registream::load_bundle(domain, lang, directory = directory)
  if (isTRUE(bundle$core_only) ||
      is.null(bundle$scope) ||
      is.null(bundle$release_sets)) {
    stop(
      "scope() requires a full v3 bundle (manifest + scope + ",
      "release_sets); the loaded bundle is core-only. Re-download via ",
      "rs_update_datasets().",
      call. = FALSE
    )
  }

  depth <- bundle$manifest$scope_depth

  # Overflow rule: depth+1 tokens → last becomes release.
  if (length(tokens) > depth && is.null(release)) {
    release <- tokens[[length(tokens)]]
    tokens  <- tokens[-length(tokens)]
  }

  if (!is.null(release)) {
    return(.variables_at_atom(bundle, tokens, release))
  }

  if (length(tokens) == 0L) {
    return(.browse_level(bundle, level_index = 1L, search = search))
  }

  res <- resolve_scope(bundle, tokens)
  scope_df <- res$scope_df

  if (length(tokens) == depth) {
    return(.releases_at_scope(scope_df))
  }

  .browse_level(
    bundle,
    level_index = length(tokens) + 1L,
    scope_df    = scope_df,
    search      = search
  )
}


.browse_level <- function(bundle,
                          level_index,
                          scope_df = NULL,
                          search   = NULL) {
  src <- if (is.null(scope_df)) bundle$scope else scope_df
  name_col  <- sprintf("scope_level_%d", level_index)
  alias_col <- sprintf("scope_level_%d_alias", level_index)

  cols <- name_col
  if (alias_col %in% colnames(src)) cols <- c(cols, alias_col)

  distinct <- unique(src[, cols, drop = FALSE])
  rownames(distinct) <- NULL

  if (!is.null(search) && nzchar(search)) {
    needle <- normalize_token(search)
    mask <- grepl(needle, normalize_token(distinct[[name_col]]), fixed = TRUE)
    mask[is.na(mask)] <- FALSE
    distinct <- distinct[mask, , drop = FALSE]
  }

  if (nrow(distinct) == 0L) return(distinct)

  rs <- bundle$release_sets[, c("release_set_id", "scope_id"), drop = FALSE]
  sc <- bundle$scope[, c("scope_id", name_col), drop = FALSE]
  rs_sc <- merge(rs, sc, by = "scope_id", sort = FALSE)
  joined <- merge(
    bundle$variables[, c("variable_name", "release_set_id"), drop = FALSE],
    rs_sc, by = "release_set_id", sort = FALSE
  )
  key <- paste(as.character(joined[[name_col]]), "\001",
               as.character(joined$variable_name), sep = "")
  joined_uniq <- joined[!duplicated(key), , drop = FALSE]
  counts_tbl <- table(as.character(joined_uniq[[name_col]]))
  counts_df <- data.frame(
    key = names(counts_tbl),
    variable_count = as.integer(unname(counts_tbl)),
    stringsAsFactors = FALSE
  )
  names(counts_df)[[1L]] <- name_col

  out <- merge(distinct, counts_df, by = name_col, all.x = TRUE, sort = FALSE)
  out$variable_count[is.na(out$variable_count)] <- 0L
  out <- out[order(out[[name_col]], method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}


.releases_at_scope <- function(scope_df) {
  cols <- "release"
  for (opt in c("release_description", "population_date")) {
    if (opt %in% colnames(scope_df)) cols <- c(cols, opt)
  }
  out <- unique(scope_df[, cols, drop = FALSE])
  out <- out[order(out$release, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}


.variables_at_atom <- function(bundle, tokens, release) {
  scope_arg <- if (length(tokens) == 0L) NULL else tokens
  filtered <- filter_bundle(bundle, scope = scope_arg, release = release)
  cols <- intersect(
    c("variable_name", "variable_label", "variable_type", "variable_unit"),
    colnames(filtered$variables)
  )
  out <- filtered$variables[, cols, drop = FALSE]
  out <- out[!duplicated(out$variable_name), , drop = FALSE]
  out <- out[order(out$variable_name, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}
