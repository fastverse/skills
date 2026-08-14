# data.table

Reference for data.table 1.18.4 as it is used *inside the fastverse* — that is,
alongside collapse, which handles most joins, reshaping and aggregation. What
follows concentrates on what data.table is uniquely good at.

Collapse functions appear here only where they are the recommended alternative.
For their arguments and semantics use the **`collapse-r`** skill — in particular
`references/join-pivot-aggregate.md` for `join`/`pivot`/`collap`/`rowbind` and
`references/efficiency.md` for `settransform`/`setv` and the by-reference
toolkit.

## Table of contents
- [The query form](#the-query-form)
- [Special symbols](#special-symbols)
- [Reference updates by reference](#reference-updates-by-reference)
- [GForce](#gforce)
- [Rolling windows: `froll*`](#rolling-windows-froll)
- [Joins](#joins)
- [The `set*` helpers](#the-set-helpers)
- [File I/O](#file-io)
- [Class-agnostic utilities](#class-agnostic-utilities)
- [Gotchas](#gotchas)

## The query form

```r
DT[i, j, by]
```

Read it as: *take `DT`, subset rows with `i`, then compute `j`, grouped by `by`.*
The three are fused — the filtered intermediate is never materialized, and the
grouped computation runs through GForce. This fusion is data.table's main claim
over a collapse pipeline, and it is worth roughly 1.6× on a filtered grouped
aggregation:

```r
d[id == "a", .(b = sum(c)), by = g]                                   #  8 ms
d |> fsubset(id == "a") |> fgroup_by(g, sort = FALSE) |>
     fsummarise(b = fsum(c, na.rm = FALSE))                           # 13 ms
```

Keep it compact. Splitting it across pipe stages is exactly what removes the
advantage.

The advantage is **the filter**, though, not the grouping. Drop `i` and collapse
comes out ahead — 12 ms vs 21 ms on a three-statistic grouped summary. So reach
for `[i, j, by]` when there is a genuine `i`, and for a collapse pipeline when
there is not.

Note the two arguments above that make the comparison honest: `by = g` returns
groups in first-appearance order (so `fgroup_by(g, sort = FALSE)`, not the
sorting default), and `sum` defaults to `na.rm = FALSE` (so `fsum(c, na.rm =
FALSE)`, since collapse defaults to `TRUE`). Unmatched, the two sides compute
different things.

| | |
|---|---|
| `i` | logical expression, row numbers, an order call, or another data.table (a join) |
| `j` | any expression; `.()` builds the output columns; `:=` updates in place |
| `by` | `by = g`, `by = .(g1, g2)`, `by = c("g1","g2")`, or an expression like `by = substr(x, 1, 2)` |
| `keyby` | as `by`, but sorts the result and sets a key on it |

```r
d[, .(m = mean(x), n = .N), by = .(region, year)]
d[, .(m = mean(x)), keyby = g]              # sorted result
d[order(-x)]                                # ordering in i
d[, .N, by = .(cut(x, 5))]                  # grouping by an expression
```

## Special symbols

| Symbol | Meaning |
|---|---|
| `.SD` | the Subset of Data for the current group — all columns except those in `by` |
| `.SDcols` | which columns go into `.SD` |
| `.N` | number of rows in the group (or in `DT` when used in `i`) |
| `.I` | row numbers in the *original* table |
| `.GRP` | group counter, 1..n |
| `.BY` | named list of the current group's `by` values |
| `.EACHI` | in `by=`, group by each row of the joining table |

```r
d[, .(grp = .GRP, n = .N), by = g]
d[, .I[which.max(x)], by = g]                # row index of the max per group
d[, lapply(.SD, sum), by = g, .SDcols = patterns("^x")]
d[, lapply(.SD, sum), by = g, .SDcols = is.numeric]
d[, lapply(.SD, sum), by = g, .SDcols = !"drop_me"]
d[, lapply(.SD, sum), by = g, .SDcols = x:y]        # column range
d[y, on = "g", .(n = sum(x > lim)), by = .EACHI]    # aggregate per row of y
```

`.SDcols` accepts names, a range, negative/`!` exclusion, a `patterns()` regex,
or a predicate function — all four forms are in daily use.

Because `.SD` is a list of columns, `j` must return a list. `lapply(.SD, mean)`
is the form GForce can optimize — substituting a collapse function there makes
it 19× slower. See
[aggregating every column of `.SD`](interop.md#aggregating-every-column-of-sd)
for the full ranking.

## Reference updates by reference

`:=` adds, modifies or deletes columns without copying the table. The `i`
argument makes it conditional, which is the thing collapse has no clean
equivalent for and therefore the strongest reason to reach for data.table:

```r
d[, area_km2 := area / 1e6]
d[source == "OSM", weight := 1 + log(value + 1)]     # conditional — the key case
d[, c("a", "b") := .(x * 2, y * 2)]                  # several at once
d[, `:=`(a = x * 2, b = y * 2)]                      # equivalent, named form
d[, (cols) := lapply(.SD, as.numeric), .SDcols = cols]   # programmatic column names
d[, c("a", "b") := NULL]                             # delete
d[, x_dm := fwithin(x, g)]                           # collapse on the RHS is fine
```

Note the parentheses in `(cols) := …`. Without them the literal name `cols` is
created.

`set()` does the same without `[.data.table` dispatch, which matters inside a
loop over many columns:

```r
for (j in names(d)) set(d, j = j, value = d[[j]] * 2)
set(d, i = which(d$x < 0), j = "x", value = 0)
```

collapse's `settransform()`/`settransformv()` do the unconditional case at the
same speed on any frame class, so use `:=` when you need `i`, or when you are
already inside a `[i, j, by]`.

## GForce

`sum`, `prod`, `mean`, `median`, `min`, `max`, `var`, `sd`, `first`, `last`,
`head`, `tail`, `weighted.mean` and `.N` in `j` are silently replaced by internal
grouped implementations. **The optimized call must be the whole expression** —
compose two and the optimization is lost for the entire `j`:

```r
d[, .(mx = max(x), mn = min(x)), by = g]     #  43 ms — optimized
d[, .(r  = max(x) - min(x)), by = g]         # 104 ms — not optimized
```

Move composed grouped expressions to collapse, which has no such restriction and
takes 28 ms for the same result — ahead of the GForce-optimized form, not just of
the un-optimized one. Confirm what happened with
`options(datatable.verbose = TRUE)`.

Subsets in `i` are separately optimized into binary searches against a key or an
automatically-built index when `getOption("datatable.optimize") >= 3` (the
default).

## Rolling windows: `froll*`

collapse has nothing here, so this is data.table's alone.

The complete API is three help pages: `?froll` (aliased `?roll`) for the
compiled family, `?frollapply` for the general one, `?frolladapt` for
calendar-aware window widths.

```r
# ?roll — nine compiled functions, one signature
frollmean(x, n, fill = NA, algo = c("fast","exact"), align = c("right","left","center"),
          na.rm = FALSE, has.nf = NA, adaptive = FALSE, partial = FALSE, give.names = FALSE)
frollsum   frollprod   frollmin   frollmax   frollmedian   frollsd   frollvar

# ?frollapply — any R function, one window at a time
frollapply(X, N, FUN, ..., by.column = TRUE, fill = NA, align = c("right","left","center"),
           adaptive = FALSE, partial = FALSE, give.names = FALSE, simplify = TRUE)

# ?frolladapt — turn a time index into per-row window widths
frolladapt(x, n, align = "right", partial = FALSE, give.names = FALSE)
```

The un-prefixed names (`rollmean`, `rollsum`, …) are documentation aliases only —
they are **not exported**; always write the `f` prefix.

```r
frollmean(x, 10)
frollmean(x, 3, align = "center")
frollmedian(x, 10, na.rm = TRUE)                  # dedicated — see below
frollapply(x, 10, mad, na.rm = TRUE)              # only when no froll* exists
frollmean(x, k_per_row, adaptive = TRUE)          # per-row window widths
frollmean(x, 3, partial = TRUE)                   # shrink the window at the boundary
frollmean(list(a = x, b = y), n = c(2, 3), give.names = TRUE)   # a_rollmean2, a_rollmean3, …
```

### Calendar-time windows on irregular data: `frolladapt`

The window `n` counts **rows**, not time. On an irregularly spaced series "the
last 3 days" and "the last 3 rows" are different questions, and `frollmean(x, 3)`
answers the wrong one. `frolladapt()` converts a `Date`/`POSIXct`/integer index
into the per-row window widths that `adaptive = TRUE` wants:

```r
d[, n3    := frolladapt(index, n = 3L)]                 # 3 *days*, in index units
d[, roll3 := frollmean(value, n3, adaptive = TRUE)]
```

On a series with gaps at 23, 24, 27, 28 Oct … this gives widths `3, 3, 1, 2, …` —
the 27th has no neighbour within 3 days, so its window is itself alone, where a
plain 3-row window would have reached back to the 24th. Units follow the index:
days for `Date`, **seconds** for `POSIXct` (truncated to whole seconds).

`x` must be sorted, with no duplicates or `NA`s, and is not vectorized — one
series at a time. `n` *is* vectorized, so `frolladapt(idx, c(small = 3, big = 7),
give.names = TRUE)` builds several width vectors at once.

This is the third option for an irregular panel, alongside padding to a complete
grid and passing `t =` to a collapse panel function — and the only one of the
three that gives calendar-correct *windows* without adding rows.

Adaptive mode has two restrictions: `align = "center"` is not implemented
(errors), and a list passed to `x` must have equal-length vectors.

### Choosing between the compiled family and `frollapply`

**Reach for `frollapply` only when there is no dedicated `froll*`.** It calls
back into R once per window; the dedicated functions run in C. Since 1.17 the
family covers mean, sum, prod, min, max, **median**, sd and var, so `median` and
`sd` no longer need `frollapply` — and the difference is not marginal:

```r
frollmedian(x, 10, na.rm = TRUE)              #   4 ms   \  identical results,
frollapply(x, 10, median, na.rm = TRUE)       # 524 ms   /  131x apart (200k rows)
```

On a grouped 1.2M-row panel the same swap is 761 ms vs 12.6 s. `mad`, `IQR` and
anything from another package still have to go through `frollapply`.

### `frollapply(by.column = FALSE)`: windows over several columns at once

By default a `data.frame` input is treated as several series to roll
independently. `by.column = FALSE` instead hands `FUN` the whole window as a
frame — which is how you do a rolling correlation, regression or covariance:

```r
frollapply(d, 3, \(w) cor(w$a, w$b), by.column = FALSE)
frollapply(d, 60, \(w) coef(lm(y ~ x, w))[2L], by.column = FALSE)
```

`simplify` controls the return type. The default `TRUE` applies an internal
simplifier; the docs recommend passing the function you actually want —
`simplify = unlist` for a vector, `simplify = FALSE` for the raw list — because
the default is kept for backward compatibility rather than predictability.

Note `frollapply`'s arguments are `X` and `N` (capitalised); the lowercase `x`
and `n` are deprecated.

**Reach for `frollapply` only when there is no dedicated `froll*`.** It calls back
into R once per window; the dedicated functions run in C. Since 1.17 the family
covers mean, sum, prod, min, max, **median**, sd and var, so `median` and `sd`
no longer need `frollapply` — and the difference is not marginal:

```r
frollmedian(x, 10, na.rm = TRUE)              #   4 ms   \  identical results,
frollapply(x, 10, median, na.rm = TRUE)       # 524 ms   /  131x apart (200k rows)
```

On a grouped 1.2M-row panel the same swap is 761 ms vs 12.6 s. `mad`, `IQR` and
anything from another package still have to go through `frollapply`. The help
page is `?froll` (also aliased `?roll`); check it before assuming a statistic
lacks a compiled version.

`froll*` is **not group-aware** — it rolls straight across group boundaries.
Wrap it in a grouping construct, and sort first:

```r
d |>
  roworder(id, year) |>
  fgroup_by(id) |>
  fmutate(across(x:z, frollmean, 10)) |>
  fungroup()
```

### The remaining arguments

**`has.nf` — and why `FALSE` is dangerous.** It declares whether `x` may contain
non-finite values (`NA`, `NaN`, `Inf`). The default `NA` runs the fast path and
silently re-runs the non-finite-aware one if it detects any, which is what you
want. `has.nf = TRUE` skips straight to the aware implementation. `has.nf = FALSE`
promises there are none — and for **`frollmax`, `frollmin` and `frollmedian` it
does not check**, so a broken promise produces a wrong answer with no warning:

```r
x <- c(1, 2, NA, 4, 5, 6)
frollmax(x, 3)                    # NA NA NA NA NA  6   correct
frollmax(x, 3, has.nf = FALSE)    # NA NA  2  4  5  6   silently wrong
```

`frollmean`/`sum`/`prod`/`var`/`sd` do detect and re-run (with a warning), so the
hazard is confined to the three order statistics. Treat
`has.nf = FALSE` on data you have not verified as undefined behaviour.
(`hasNA` is the deprecated spelling; it warns.)

**`partial = TRUE`** shrinks the window at the boundary instead of returning
`fill`. It is implemented *via* the adaptive machinery, so it inherits adaptive's
restrictions and its cost — the docs suggest computing the boundary values
separately afterwards if performance matters.

**`algo = "exact"`** is slower but avoids the accumulated floating-point drift of
the running-sum algorithm; use it when the window is long and values vary by
orders of magnitude.

**Parallelism.** Multiple columns or multiple window widths are processed in
parallel; `algo = "exact"` and `adaptive = TRUE` parallelize even for a single
column and width. This uses `getDTthreads()` — half the cores by default — so it
is another reason not to nest a multithreaded collapse call inside a rolling
computation. `options(datatable.verbose = TRUE)` reports what the rolling
function did, printed at the end rather than live.

**Non-atomic input goes column by column.** `frollmean(d, 3)` on a
`data.frame`/`list` rolls each column separately and returns a list — it does not
roll across columns. That is what `frollapply(by.column = FALSE)` is for.

## Joins

For plain equi-joins prefer `collapse::join()` — it is faster, prints a match
report, preserves `x`'s row order and can `validate` the cardinality. Use
data.table for the join types collapse does not have.

```r
setkey(x, id); setkey(y, id)
y[x]                        # right/left depending on which side you index
x[y, on = "id"]             # ad-hoc join, no key needed
x[y, on = "id", nomatch = NULL]   # inner
```

**Rolling join** — carry the last observation forward in time, the classic
as-of join for prices, exchange rates, or any state variable:

```r
setkey(prices, sym, t); setkey(trades, sym, t)
prices[trades, roll = TRUE]                   # last value at or before each trade
prices[trades, roll = -Inf]                   # next value at or after
prices[trades, roll = 5]                      # only if within 5 time units
prices[trades, roll = TRUE, rollends = c(TRUE, TRUE)]   # extend past both ends
```

**Non-equi join** — match on inequalities:

```r
b[a, on = .(v >= lo, v <= hi), .(id, v = x.v), nomatch = NULL]
```

`x.` prefixes a column of the outer table when both sides carry the name.

**`foverlaps()`** — interval overlap join, for date ranges or genomic intervals:

```r
setkey(x, id, start, end)
foverlaps(y, x, by.x = c("id","start","end"), type = "any", nomatch = NULL)
```

`type` is one of `"any"`, `"within"`, `"start"`, `"end"`, `"equal"`.

## The `set*` helpers

All modify in place and return invisibly.

```r
setDT(df)            setDF(dt)              # convert without copying
setnames(d, old, new)                       # rename; `skip_absent = TRUE` to be lenient
setcolorder(d, neworder)
setorder(d, a, -b)   setorderv(d, cols, order = c(1, -1))
setkey(d, a, b)      setkeyv(d, cols)       # sort + mark for binary search
setindex(d, a)       setindexv(d, cols)     # index without reordering
setattr(x, "name", value)                   # set an attribute with no copy — works on any object
setalloccol(d)                              # re-over-allocate after a class-losing operation
setDTthreads(n)      getDTthreads()
```

`setattr()` is worth knowing beyond data.table: it is the only base-R-free way
to set an attribute on any object without copying it.

## File I/O

```r
fread(input, sep = "auto", nrows = Inf, header = "auto", select = NULL, drop = NULL,
      colClasses = NULL, na.strings = "NA", nThread = getDTthreads(), showProgress = TRUE)
fwrite(x, file = "", sep = ",", quote = "auto", compress = "auto", nThread = getDTthreads())
```

```r
fread("data.csv", select = c("id", "value"))       # read only what you need
fread("data.csv", colClasses = c(id = "character"))   # stop it inferring numeric IDs
fread(cmd = "grep 2023 big.csv")                   # pre-filter with a shell command
fwrite(d, "out.csv.gz")                            # compression from the extension
```

`select =` is the single biggest win on wide files — parsing is skipped
entirely for unselected columns.

## Class-agnostic utilities

These take plain vectors, lists or data frames and are fine to use anywhere,
including on `sf` objects, tibbles and matrices:

```r
fifelse(test, yes, no, na = NA)          # vectorized ifelse
fcase(when1, value1, when2, value2, ..., default = NA)
fcoalesce(...)                           # first non-NA — 4 ms/5M, the fastest coalesce here
shift(x, n = 1, type = c("lag","lead","shift","cyclic"))
nafill(x, type = c("const","locf","nocb"), fill = NA)
setnafill(x, ...)                        # in place
between(x, lower, upper, incbounds = TRUE)     # also %between%
inrange(x, start, end)
rleid(...)      # run-length group id:  a a b a -> 1 1 2 3
rowid(...)      # within-group counter: a a b a -> 1 2 1 3
uniqueN(x)
transpose(l, keep.names = NULL, make.names = NULL)   # lists and data frames, NOT matrices
tstrsplit(x, split, fixed = TRUE, keep = NULL)       # split into columns
CJ(...)         # cross join / expand.grid, optionally sorted and keyed
copy(x)         # deep copy — the only way to detach a data.table from its aliases
frev(x)         chmatch(x, table)         fsort(x)
```

`rleid` and `rowid` are easy to confuse: `rleid` increments on every *change*,
`rowid` counts occurrences of each value. Neither has a collapse equivalent
(`GRPid()` gives the group index, which is a third thing).

## Gotchas

**1. `d2 <- d` is not a copy.** Both names point at the same table, and any `:=`
or `set*()` changes both. `copy(d)` is the only fix. Functions that take a
data.table and modify it by reference change their caller's object — that is
intentional, but it must be documented.

**2. `d$col <- v` silently copies the whole table; `:=` does not.** The copy is
the reason to avoid `$<-` on a large data.table — and it is invisible, since as
of 1.18.4 `$<-.data.table` handles the over-allocation itself and issues **no**
warning. Verify with `address()` rather than waiting to be told:

```r
before <- address(d); d$top <- d$score * 2; before != address(d)   # TRUE — copied
before <- address(d); d[, top := score * 2]; before != address(d)  # FALSE — in place
```

The related `Invalid .internal.selfref` / "shallow copy was taken" warning still
exists, but it fires for a different cause: a table built by `structure()`, or
mutated by `attr<-`/`names<-`, which strips the over-allocation. `setalloccol(d)`
repairs that. collapse verbs preserve it, so a collapse → `:=` chain is safe.

**3. `hasNA` is deprecated in `froll*`.** Use `has.nf` (it covers `NaN` and
`Inf` too). The old name still works but warns.

**4. `merge()` sorts and sets a key.** If downstream code relies on row order,
either pass `sort = FALSE` or use `collapse::join()`, which preserves `x`'s
order by default.

**5. GForce is all-or-nothing per `j` expression.** See above.

**6. A `by` group's columns are not in `.SD`.** If you need a `by` column inside
`j`, use `.BY$name`, or add it to `.SDcols`.

**7. `.N` in `i` means something different** — the number of rows in the whole
table, so `d[.N]` is the last row and `d[, .N]` is `nrow(d)`.

**8. Printing a data.table from inside a function or a loop needs an extra
`[]`** — `d[, x := 1][]` — because `:=` returns invisibly.
