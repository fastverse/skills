# Making the four packages work together

This file is about **choosing between** the packages. For how any collapse
function actually behaves — its arguments, its defaults, its edge cases — use the
**`collapse-r`** skill; the collapse code below is illustrative, not a spec.

Everything here was measured on collapse 2.1.7 / data.table 1.18.4 / kit 0.0.21,
macOS, collapse compiled with OpenMP, kit without. Timings are medians of 3–5
runs; treat the ratios as the signal, not the absolute numbers.

**Matching the two packages' defaults before timing them.** Two defaults differ
and both distort a naive comparison:

- **Group order.** `by = g` returns groups in first-appearance order;
  `fgroup_by(g)` sorts. The matched pairs are `by =` ↔ `fgroup_by(g, sort = FALSE)`
  and `keyby =` ↔ `fgroup_by(g)`.
- **Missing values.** `sum`/`mean`/`max` default to `na.rm = FALSE`; every
  collapse Fast Statistical Function defaults to `na.rm = TRUE`.

Unmatched, you are timing a sort and a missing-value scan the other side never
ran — and, more importantly, getting **different answers** on data containing
`NA`s. Every comparison below is matched, and the results were checked identical
including row order.

## Table of contents
- [The decision table](#the-decision-table)
- [Calling collapse inside a data.table query](#calling-collapse-inside-a-datatable-query)
- [Aggregating every column of `.SD`](#aggregating-every-column-of-sd)
- [GForce and when it switches off](#gforce-and-when-it-switches-off)
- [Grouped rolling windows](#grouped-rolling-windows)
- [Classes, keys and attributes](#classes-keys-and-attributes)
- [Non-data.table objects: sf, matrices, tibbles](#non-datatable-objects-sf-matrices-tibbles)
- [Reference semantics across the two packages](#reference-semantics-across-the-two-packages)
- [Threading interactions](#threading-interactions)

## The decision table

| You want to… | Use | Why not the other |
|---|---|---|
| Join on equal keys | `join()` | `merge()` sorts and re-keys the result; no match report, no `validate` |
| Rolling / non-equi join, `foverlaps` | data.table | `join()` is equi-only |
| Reshape | `pivot()` | `dcast()` is 16× slower on wide targets; `melt` drops variable labels |
| Filter + aggregate + group in one step | `d[i, j, by]` | collapse materializes the filtered frame first — 8 vs 13 ms |
| Aggregate without a filter | `fgroup_by() \|> fsummarise()` | faster once matched — 12 vs 21 ms — and composes |
| Aggregate a composed expression per group | collapse | GForce switches off — 28 vs 104 ms |
| Add/modify a column unconditionally | either | `settransform` ≈ `:=` (3 vs 4 ms) |
| Modify a column **for some rows only** | `d[i, col := v]` | no clean collapse equivalent |
| Rolling window statistics | `froll*` | collapse has none |
| Row-wise statistic across columns | `kit::psum` etc. | collapse aggregates down columns, not across |
| Top-N indices | `kit::topn` | `order()[1:n]` is 23× slower |
| Recode many values 1:1 | `vswitch`/`nswitch` | ~3× faster than `fcase`, 2× faster than `nif` |
| Distinct rows / stack / drop levels | `funique`/`rowbind`/`fdroplevels` | collapse versions are faster and class-agnostic |
| Read/write delimited files | `fread`/`fwrite` | nothing else comes close |

## Calling collapse inside a data.table query

This is the most productive combination in the whole stack: data.table supplies
the grouping and row-filtering machinery, collapse supplies a vectorized
statistic that data.table has no GForce version of.

```r
# collapse statistic over .SD, grouped by a data.table by=
d[Year < 2020, qDF(pwcor(.SD, N = TRUE), "variable"), by = .(region, country),
  .SDcols = vars]

# collapse subsetting inside j — one row per group
d[Source %in% c("AGR", "IND", "SRV"), ss(.SD, which.max(MAD)), by = ISO3]

# collapse operators in i
d[g %==% "a"]                  # faster than g == "a" for a single value
d[x %iin% c(1, 3)]             # faster %in%
d[harm_cat %!in% drop_these]

# collapse RHS in a := update
d[, x_demeaned := fwithin(x, g)]
d[, paste0("HP_cycle_", vars) := lapply(get_vars(.SD, vars), hp_cycle), by = iso3c]
```

`kit::topn` composes the same way — it returns row indices, so it goes in `i`:

```r
d[topn(value, 10)]                            # global top 10
d |> extract(j = .SD[topn(value, 10)], by = .(outcome, type))   # top 10 per group
```

## Aggregating every column of `.SD`

"Mean of each column, by group" is the most common `.SD` job and the one where
the intuitive choice is worst. On 5M rows / 100k groups / 4 columns, matched for
group order and `na.rm`, with all results verified identical including row order:

```r
# unsorted groups — matches data.table's by=
d |> fgroup_by(g, sort = FALSE) |> fselect(x, y, z, w) |> fmean(na.rm = FALSE)        # 31 ms
d |> fgroup_by(g, sort = FALSE) |> fsummarise(across(c(x,y,z,w), fmean, na.rm = FALSE)) # 32 ms
d[, fmean(.SD, gu, na.rm = FALSE), .SDcols = c("x","y","z","w")]  # gu <- qF(d$g, sort = FALSE)  31 ms
d[, lapply(.SD, mean), by = g]                                                        # 36 ms

# sorted groups — matches data.table's keyby=
d |> fgroup_by(g) |> fselect(x, y, z, w) |> fmean(na.rm = FALSE)                      # 34 ms
d[, lapply(.SD, mean), keyby = g]                                                     # 33 ms

# avoid — correct answers, but GForce is off
d[, fmean(.SD, drop = FALSE, na.rm = FALSE), by = g]                                  # 303 ms
d[, lapply(.SD, fmean, na.rm = FALSE), by = g]                                        # 674 ms
```

So on speed the routes are effectively tied, and the native collapse pipeline is
slightly ahead in the unsorted case. **Choose on clarity, not speed** — which is
why the collapse route is the recommendation: it composes, it works on any frame
class, and there is no `.SD` to reason about.

One wrinkle in the third form: because collapse does the grouping and there is no
`by=`, the result comes back **without a group column** — you get the four
aggregated columns and nothing to identify the rows. Put it back explicitly, or
use one of the other routes:

```r
d[, c(list(g = funique(d$g)), fmean(.SD, gu, na.rm = FALSE)), .SDcols = c("x","y")]
```

Take the labels from the original column, not from `gu` — `funique(gu)` returns a
*factor*, so the group column comes back with a different type than `by = g`
would have given.

**`lapply(.SD, mean)` is the one form data.table can optimize.** It rewrites the
`lapply` into `list(mean(x), mean(y), …)` and then each `mean` into `gmean` —
you can watch it happen with `options(datatable.verbose = TRUE)`:

```
lapply optimization changed j from 'lapply(.SD, mean)' to 'list(mean(x), mean(y), ...)'
GForce optimized j to 'list(gmean(x), gmean(y), ...)'
```

Substituting `fmean` breaks that chain — GForce only recognises the base names,
so `lapply(.SD, fmean)` calls the function once per group and takes 19× longer
than `lapply(.SD, mean)`. Reaching for the "fast" function inside `by=` is
actively counterproductive.

**The `na.rm` defaults differ, so these routes are not interchangeable.**
`mean()` defaults to `na.rm = FALSE`, every collapse Fast Statistical Function
to `na.rm = TRUE`:

```r
d <- data.table(g = c("a","a","b"), x = c(1, NA, 3))
d[, lapply(.SD, mean), by = g]$x               # NA  3
d[, lapply(.SD, mean, na.rm = TRUE), by = g]$x #  1  3   <- matches collapse
d[, fmean(.SD, g), .SDcols = "x"]$x            #  1  3
```

Write `na.rm = TRUE` explicitly when moving a pipeline between the two.

**Why `drop = FALSE`.** A collapse Fast Statistical Function on a data frame
returns a plain named vector when there is no grouping — and `j` must return a
list, so data.table stacks that vector vertically and the column identity is
lost:

```r
d[, fmean(.SD), by = g]
#         g    V1        <- 4 rows, not 2: the x-mean and y-mean stacked
```

`drop = FALSE` keeps it a one-row data frame and fixes the shape. It is the
right answer to the shape question and the wrong answer to the speed question,
which is why option 4 above exists but is not recommended. The underlying rule:
**a collapse function returns a frame when you pass it `g` (or `drop = FALSE`),
and a bare vector when you don't** — which is why `fmean(.SD, rowid(feature))`
drops into `j` with no wrapping at all.

All of these error with `Unsupported SEXP type: 'character'` if a non-numeric
column is in scope, so select first — `.SDcols =` in the data.table forms,
`fselect()`/`num_vars()` in the collapse ones.

## GForce and when it switches off

data.table replaces `sum`, `prod`, `mean`, `median`, `min`, `max`, `var`, `sd`,
`first`, `last`, `head`, `tail`, `weighted.mean` and `.N` in `j` with internal
grouped versions ("GForce") that compute per group without ever splitting the
data. That is why `d[, .(m = sum(x)), by = g]` is so fast.

It has a hard limitation: **the optimized function must be the whole
expression.** Compose two of them and the optimization is lost for the entire
`j`, and data.table falls back to evaluating the expression once per group:

```r
d[, .(mx = max(x), mn = min(x)), by = g]                 #  43 ms — GForce
d[, .(r  = max(x) - min(x)), by = g]                     # 104 ms — no GForce
d |> fgroup_by(g, sort = FALSE) |>
     fsummarise(r = fmax(x, na.rm = FALSE) -
                    fmin(x, na.rm = FALSE))              #  28 ms — no such limit
```

collapse has no equivalent restriction because `fsummarise` vectorizes each Fast
Statistical Function call independently and then evaluates the arithmetic on the
already-aggregated vectors. Note that it comes out ahead of the GForce-optimized
form too, not merely of the un-optimized one. So: **the moment a grouped `j`
expression is more than a single optimized call, move it to collapse.**

The same holds for a plain multi-statistic summary, where nothing is composed and
GForce is fully active:

```r
d[, .(m = mean(x), s = sum(c), n = .N), by = g]                        # 21 ms
d |> fgroup_by(g, sort = FALSE) |>
     fsummarise(m = fmean(x, na.rm = FALSE),
                s = fsum(c, na.rm = FALSE), n = GRPN())                # 12 ms
```

**What data.table's query form actually buys you is the fused filter**, not the
grouped aggregation. Put a filter back in and it wins:

```r
d[id == "a", .(b = sum(c)), by = g]                                    #  8 ms
d |> fsubset(id == "a") |> fgroup_by(g, sort = FALSE) |>
     fsummarise(b = fsum(c, na.rm = FALSE))                            # 13 ms
```

The same applies to any function that has no GForce version at all — `mad`,
`IQR`, `quantile` with an arbitrary probability, anything from another package.
Those run once per group either way, so the choice is stylistic (2118 ms for
`d[, .(m = mad(x)), by = g]` vs 2141 ms for `BY(d$x, d$g, mad)` on 5M rows /
100k groups — identical, both slow).

Check what got optimized with `options(datatable.verbose = TRUE)`.

## Grouped rolling windows

data.table's `froll*` functions are not group-aware — they roll straight through
group boundaries. Two correct patterns; the collapse one composes better and is
what the research code settled on:

```r
# collapse orchestrates, data.table computes  (preferred)
d |>
  roworder(ISO3, Year) |>
  fgroup_by(ISO3, return.groups = FALSE) |>
  fmutate(across(INFL:PCGDP_G, frollmean, 10),
          across(c(PCGDP_G, INFL),
                 list(MED = \(x) frollmedian(x, 10, na.rm = TRUE),
                      MAD = \(x) frollapply(x, 10, mad, na.rm = TRUE)))) |>
  fungroup()

# pure data.table — note you must carry the time column through yourself
d[Year < 2020,
  c(list(Year = Year), lapply(.SD, frollmean, 10)),
  by = ISO3, .SDcols = -(1:2)]
```

`roworder()` first is not optional — a rolling window over unsorted rows is
meaningless, and neither package will warn you.

## Classes, keys and attributes

| Operation | data.table class | key |
|---|---|---|
| `fmutate`, `ftransform`, `fselect` | preserved | preserved |
| `fsubset` | preserved | **dropped** |
| `d[i]` | preserved | preserved |
| `roworder`, `setorder` | preserved | dropped (order changed) |
| `fgroup_by() \|> fsummarise()` | preserved | n/a |
| `join` | preserved (from `x`) | dropped |
| `merge` | preserved | **set to the join columns** |

`fsubset()` dropping the key while `d[i]` keeps it is the asymmetry to remember.
If a later step depends on binary search, `setkey()` again or use `[`.

collapse calls data.table's own over-allocation routine on frames it returns, so
you can follow any collapse verb with `:=` without the shallow-copy /
`Invalid .internal.selfref` warning, and without a hidden copy:

```r
d |> fselect(id, v) |> extract(, w := v * 2)   # no warning, no copy
```

## Non-data.table objects: sf, matrices, tibbles

The class-agnostic half of the stack is collapse plus a handful of data.table
functions (`transpose`, `fifelse`, `fcase`, `fcoalesce`, `froll*`, `nafill`,
`shift`, `between`) plus all of kit. Between them you can do most work without
ever converting.

**`sf` data frames.** Row-preserving collapse verbs keep the class, the geometry
column and the CRS, so no conversion is needed:

```r
pts |> fsubset(area > 1e3)              # still sf, CRS intact
pts |> fmutate(area_km2 = area / 1e6)   # still sf
```

Row-reducing verbs need a decision about the geometry, because collapse will not
guess. Either aggregate it alongside everything else:

```r
pts |> fgroup_by(cat) |> fsummarise(n = GRPN(), geometry = st_union(geometry))
pts |> fgroup_by(cat) |> fsummarise(n = GRPN(), geometry = ffirst(geometry))
```

`st_union()` is a genuine dissolve — the result is a valid `sf` object with the
CRS intact, and the dissolved areas sum to the areas of the parts. `ffirst()`
keeps one representative geometry per group, which is what you want when the
rows in a group already share a geometry (points snapped to a grid cell, records
for the same admin unit).

Or set the geometry aside by converting **at the start** of the pipeline:

```r
pts |> qDT() |> fgroup_by(cat) |> fsummarise(n = GRPN(), area = fsum(area))
```

`qDF()`, `qDT()` and `qTBL()` strip the `sf` class but **keep the geometry as an
`sfc` list column**, so nothing is discarded and `st_as_sf()` restores the object
later. (`st_drop_geometry()` also works, but it actually removes the column —
prefer the `q*` conversions if you might want the geometry back.)

Do neither and it fails quietly: the geometry is dropped while the `sf` class and
its `sf_column` attribute stay behind, and the result throws
`attr(obj, "sf_column") does not point to a geometry column` the first time it is
printed. `fcount()` on an `sf` object errors immediately instead
(`Unsupported types: character and list`), because it tries to hash the geometry
list — `qDT()` first.

```r
pts |> fgroup_by(cat) |> fsummarise(n = GRPN())   # BROKEN sf — errors when printed
pts |> fcount(cat)                                # errors outright
```

**Matrices.** collapse's statistical functions have `.matrix` methods, so
`fsum(m, g)`, `fmean(m)`, `fscale(m)` all work and return matrices. For the row
direction use kit. `kit::funique()` handles matrices where `collapse::funique()`
errors. `data.table::transpose()` does **not** take a matrix (use `t()`); it is
for lists and data frames.

**Tibbles / grouped_df.** collapse dispatches on `grouped_df`, so a dplyr
pipeline can hand off mid-stream. No conversion needed.

The one thing that genuinely requires a data.table is `:=`. If you need
conditional reference updates on a tibble or sf object, either accept a copy via
`fmutate` or convert deliberately and convert back, knowing what it costs.

## Reference semantics across the two packages

Both packages modify in place, with different notation:

```r
d[, y := x * 2]                      # data.table
settransform(d, y = x * 2)           # collapse, same effect, works on any frame
d[, y := x * 2][, z := y + 1]        # chaining
d |> fsum(g, TRA = "/", set = TRUE)  # collapse: divide every column by its group sum, in place
setv(x, 5, 0)                        # replace value 5 with 0, in place
x %+=% y                             # in-place arithmetic
setop(X, "*", v)                     # v recycled down columns  (length(v) == nrow(X))
setop(X, "*", v, rowwise = TRUE)     # v applied along each row (length(v) == ncol(X))
```

The collapse half of that list — `settransform`, `setv`, `copyv`, `setop`,
`%+=%`, `set = TRUE`, `alloc` — belongs to **`collapse-r`**, which documents the
signatures, the chaining rules and the iterative-fitting pattern in
`references/efficiency.md`. Go there before using one; what matters *here* is
only that both packages have a by-reference mode and that they compose.

One trap that spans both, so it is worth repeating: **assignment is not a copy.**
`d2 <- d` gives two names for one object, and a `:=` or a `set*()` on either
changes both. `copy(d)` is the only way to get an independent data.table.
collapse's `fmutate`/`ftransform` do copy, which is why they are safe by default —
their `set*` counterparts are not.

## Threading interactions

```r
setDTthreads(4)              # data.table
set_collapse(nthreads = 4)   # collapse
options(kit.nThread = 4L)    # kit — integer only
```

Do not nest them. data.table parallelizes over groups in `by=`; a multithreaded
collapse or kit call inside that `j` competes with it for the same cores and
usually ends up slower. Keep the inner call at one thread.

On macOS, CRAN binaries of collapse and kit have no OpenMP at all — kit says so
when it attaches (`OPENMP disabled using 1 thread`), collapse does not announce
it. Test rather than assume:

```r
x <- rnorm(1e7)
system.time(fsum(x, nthreads = 1))
system.time(fsum(x, nthreads = 4))   # same time => no OpenMP
```

Note also that multithreading helps far less than people expect for *grouped*
work — the grouping itself is serial. It pays off mainly for large ungrouped
vector operations.
