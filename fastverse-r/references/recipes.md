# Recipes

Patterns that involve **more than one** fastverse package, lifted from
production research code. Single-package collapse patterns live in the
`collapse-r` skill's `references/recipes.md` — this file does not repeat them.

Every block below was run against collapse 2.1.7 / data.table 1.18.4 /
kit 0.0.21.

## Table of contents
- [Script header](#script-header)
- [Reading and binding many files](#reading-and-binding-many-files)
- [Grouped rolling statistics](#grouped-rolling-statistics)
- [Top-N rows per group](#top-n-rows-per-group)
- [Coalescing and recoding columns](#coalescing-and-recoding-columns)
- [Row-wise statistics across a block of columns](#row-wise-statistics-across-a-block-of-columns)
- [Conditional updates by reference](#conditional-updates-by-reference)
- [Panel work: lag, then roll](#panel-work-lag-then-roll)
- [Aggregating a grid or spatial layer](#aggregating-a-grid-or-spatial-layer)
- [Matrices and input-output tables](#matrices-and-input-output-tables)
- [Wide correlation tables](#wide-correlation-tables)

## Script header

What the research scripts actually start with:

```r
library(fastverse)                        # data.table, magrittr, kit, collapse
fastverse_extend(sf, s2, fixest)          # project-specific, with versions + conflicts printed
```

If the project has a `.fastverse` file, `library(fastverse)` alone loads the
whole stack and sets the options — do not add `fastverse_extend()` calls for
packages already listed there. Match the project's existing convention rather
than introducing a new one, and do not add `setDTthreads()` or `set_collapse()`
to someone's script unless they asked.

## Reading and binding many files

`fread` per file, then `rowbind` with an id column naming the source. `rowbind`
beats `rbindlist` (9 ms vs 19 ms on 50 × 100k) and takes `idcol` the same way:

```r
files <- list.files("data/raw", pattern = "\\.csv$", full.names = TRUE)

d <- files |>
  lapply(fread) |>
  set_names(tools::file_path_sans_ext(basename(files))) |>
  rowbind(idcol = "ISO3")
```

`set_names()` is magrittr's; the names become the `idcol` values. For a nested
list (e.g. files inside country folders) use `unlist2d()` from collapse, which
flattens arbitrarily deep and makes one id column per level.

Read narrow when the file is wide — `select` skips parsing entirely:

```r
v <- fread(path, select = c("year", "from_region", "from_sector", "gvc"))
fread(cmd = "unzip -p data/relative-wealth-index.zip")     # decompress in a pipe
fread(path, colClasses = c(id = "character"))              # stop IDs becoming numeric
```

## Grouped rolling statistics

`froll*` is not group-aware, so wrap it. collapse orchestrates, data.table
computes. **Sort first** — a rolling window over unsorted rows is meaningless
and nothing warns you:

```r
d |>
  roworder(ISO3, Year) |>
  fgroup_by(ISO3, return.groups = FALSE) |>
  fmutate(across(INFL:PCGDP_G, frollmean, 10),
          across(c(PCGDP_G, INFL),
                 list(MED = \(x) frollmedian(x, 10, na.rm = TRUE),
                      MAD = \(x) frollapply(x, 10, mad, na.rm = TRUE)))) |>
  fungroup() |>
  na_omit(cols = c("PCGDP_G", "INFL"))
```

`across(cols, list(NAME = fun, ...))` suffixes the results, so you get
`PCGDP_G_MED`, `PCGDP_G_MAD`, ….

The pure data.table form is equivalent but you must carry the time column
through by hand, because `.SD` excludes only the `by` columns:

```r
d[Year < 2020,
  c(list(Year = Year), lapply(.SD, frollmean, 10)),
  by = .(Country, ISO3), .SDcols = .c(GDP, AGR, IND, SRV)]
```

## Top-N rows per group

Three routes, all correct, in order of preference:

```r
# collapse — clearest, and how = "max"/"min" makes the intent explicit
fslice(d, g, n = 2, order.by = v, how = "max")

# kit inside a data.table j — the fastest for small n on a large table
d |> extract(j = .SD[topn(v, 2)], by = g)

# base idiom, fine for n = 1
d[, .SD[which.max(v)], by = g]
```

`fslice`'s `order.by` is only consulted when `how` is `"min"` or `"max"` — with
the default `how = "first"` it is ignored and you silently get the first `n`
rows in current order. This is easy to get wrong.

`topn()` returns indices and defaults to `decreasing = TRUE`, so `topn(v, 2)` is
the two largest.

## Coalescing and recoding columns

```r
d |>
  fmutate(industrial      = pfirst(mining_industrial, industrial),
          transport_other = pfirst(transport_shipping, transport_other),
          mining_industrial = NULL, transport_shipping = NULL)
```

`pfirst()` takes the first non-missing across the arguments. `fcoalesce()` is
about twice as fast for plain atomic vectors; `pfirst` handles lists and
factors (which must share levels).

Recoding many values at once — `vswitch` is ~3× `fcase`:

```r
d |> fmutate(
  iso3   = vswitch(iso3, c("ZAR","TMP","ROM","MNT"), c("COD","TLS","ROU","MNE"), default = iso3),
  sector = nswitch(sector, "EGW","SRV", "SMH","SRV", "TRA","SRV", "PTE","SRV", default = sector)
)
```

For a **factor**, recode the levels rather than the values — far cheaper on a
long vector:

```r
levels(d$iso3) <- vswitch(levels(d$iso3), c("ZAR","TMP"), c("COD","TLS"), default = levels(d$iso3))
```

When the mapping lives in a named list of groups:

```r
vswitch(x, unlist(sec_map), rep(names(sec_map), lengths(sec_map)), default = x)
```

## Row-wise statistics across a block of columns

kit's p-functions take a data frame directly, so a collapse column selection
feeds straight in:

```r
# keep rows with any activity across a block of indicator columns
d |> fsubset(psum(fselect(d, accommodation:waste)) > 0)

# significance stars
d |> fmutate(stars = psum(p < 0.01, p < 0.05, p < 0.1))

# drop rows missing any of a set of key columns
d |> fsubset(!panyNA(fselect(d, x1, x2, x3)))

# row totals, then a share of the total
d |> fmutate(total = psum(fselect(d, starts_with("cat_"))),
             share = value / total)
```

`psum(d[, cols])` and `psum(a, b, c)` are the same call — a single list argument
or several vectors.

Remember these do not recycle: a length-1 argument is an error, not a broadcast.

## Conditional updates by reference

The one thing collapse has no clean equivalent for, and therefore the clearest
reason to have a data.table:

```r
d[, weight := 1]
d[source %in% c("GIP","GPP","GSP"), weight := 1 + log(replace_na(value) + 1) / 1e5]
d[harm_cat %==% "port", id := paste(harm_cat, rowid(harm_cat), sep = "_")]
d[is.na(population), population := 1000]
```

Note `%==%` (collapse) inside `i` — it is faster than `==` for a single value
and returns no `NA`s. `rowid()` (data.table) numbers the occurrences within each
value, giving `port_1`, `port_2`, ….

For the unconditional case either package is fine and equally fast:

```r
d[, area_km2 := area / 1e6]
settransform(d, area_km2 = area / 1e6)      # same, and works on any frame class
```

## Panel work: lag, then roll

collapse handles the panel structure, data.table handles the window. Do the
whole thing in **one** grouped `fmutate` — later expressions see columns created
by earlier ones in the same call:

```r
d |>
  roworder(id, year) |>
  fgroup_by(id, return.groups = FALSE) |>
  fmutate(dx  = fdiff(x, t = year),
          vol = frollsd(dx, 10, na.rm = TRUE)) |>
  fungroup()
```

Three things this gets right that a split pipeline does not: `dx` is computed and
consumed inside one grouping pass rather than two; `return.groups = FALSE` skips
materializing the group labels you are not going to use; and `frollsd` is the
compiled version of what `frollapply(dx, 10, sd)` does by calling R once per
window.

`t = year` protects against differencing across a gap in an unbalanced panel.
`froll*` has no such protection — it always assumes consecutive rows. That
asymmetry is the thing to think about, and it has a corollary worth stating,
because it is the opposite of "always pass `t`":

**If you regularise the panel, stop passing `t`.** Padding to a complete
`min(year):max(year)` grid makes row position and calendar time coincide, at
which point `t` is doing redundant work — it re-derives an index that is now
just the row order. Same answer, measurably slower:

```r
fgrowth(PCGDP, g = ISO3)            #  4 ms  \  identical results on a
fgrowth(PCGDP, g = ISO3, t = Year)  # 13 ms  /  regular panel — 3.25x
```

So: pad *or* pass `t`, not both. Padding is worth it when several rolling
statistics follow (they all need positional regularity anyway); passing `t` is
better when you only need one or two panel operations and would rather not grow
the table.

There is a **third option that neither pads nor relies on `t`**: build
calendar-aware window widths with `frolladapt()` and roll adaptively. This is the
only route that makes the *windows* calendar-correct without adding rows —
`t =` protects the growth rate but does nothing for the rolling window, which is
why padding is otherwise necessary:

```r
wdi |>
  roworder(ISO3, Year) |>
  fgroup_by(ISO3, return.groups = FALSE) |>
  fmutate(PCGDP_G     = fgrowth(PCGDP, t = Year),
          w10         = frolladapt(Year, 10L),          # 10 *years*, per row
          PCGDP_G_MED = frollmedian(PCGDP_G, w10, adaptive = TRUE, na.rm = TRUE),
          PCGDP_G_MAD = frollapply(PCGDP_G, w10, mad, adaptive = TRUE, na.rm = TRUE),
          INFL_MED    = frollmedian(INFL,    w10, adaptive = TRUE, na.rm = TRUE),
          INFL_MAD    = frollapply(INFL,     w10, mad, adaptive = TRUE, na.rm = TRUE),
          w10 = NULL) |>
  fungroup() |>
  na_omit(cols = c("PCGDP_G_MED", "PCGDP_G_MAD", "INFL_MED", "INFL_MAD"))
```

This returns **bit-identical results** to the padded version — verified across
panels from 12% to 80% missing years — while never growing the table, and it
drops the `join`, the `.real` marker column and the `fsubset` that strips the
filler rows again. The advantage scales with sparsity:

| Years missing | Real rows | Padded rows | Padded | `frolladapt` |
|---|---|---|---|---|
| 12% | 16,032 | 18,226 (+14%) | 626 ms | 546 ms |
| 35% | 11,845 | 17,984 (+52%) | 611 ms | 415 ms |
| 60% | 7,329 | 17,435 (+138%) | 537 ms | 252 ms |
| 80% | 3,655 | 15,749 (+331%) | 380 ms | 125 ms |

Note `t = Year` comes *back* here: the panel is genuinely irregular now, so
`fgrowth` needs it. `frolladapt` handles the windows, `t =` handles the lag —
they solve different halves of the problem.

Units follow the index — days for `Date`, seconds for `POSIXct`. The index must
be sorted with no duplicates within each group, which `roworder()` gives you.
One wrinkle: `across()` lambdas cannot see a column created earlier in the *same*
`fmutate`, so either name the four columns explicitly as above, or compute the
widths in a first `fmutate` and keep `across()` in a second — the grouping is
computed once either way.

```r
# pad once, then everything downstream is positional
wdi <- join(wdi[, .(Year = seq.int(min(Year), max(Year))), by = ISO3], wdi,
            on = c("ISO3", "Year"), how = "left", verbose = 0) |>
  roworder(ISO3, Year) |>
  fgroup_by(ISO3, return.groups = FALSE) |>
  fmutate(g   = fgrowth(PCGDP),                       # no t = needed now
          med = frollmedian(g, 10, na.rm = TRUE),
          mad = frollapply(g, 10, mad, na.rm = TRUE)) |>
  fungroup()
```

Note the grid expression goes **straight into `join()`** rather than into a
`year_grid` object first, and the result overwrites `wdi` rather than
accumulating `wdi_pad`, `wdi_real`, `wdi_final`. On a panel of any size those
intermediates are full copies sitting in memory for no reason — keep the one
object you need, or `rm()` the rest.

## Aggregating a grid or spatial layer

Keep the `sf` object as `sf` for row-preserving work — no conversion needed:

```r
pts <- pts |>
  fmutate(cell = dgGEO_to_SEQNUM(hex_grid, lon, lat)$seqnum) |>
  fsubset(between(lon, -20, 53) & between(lat, -37, 38))
```

When you aggregate, say what happens to the geometry. If the output is a table,
convert at the top of the pipeline — `qDT()` keeps the geometry as an `sfc` list
column, so it is set aside rather than thrown away:

```r
cell_stats <- pts |>
  qDT() |>
  fgroup_by(cell, category) |>
  fsummarise(n = GRPN(), area = fsum(area), value = fmean(value, w = pop))
```

If the output should still be a map, aggregate the geometry too — `st_union()`
to dissolve, or `ffirst()` when the rows in a group already share a geometry
(which is the case for points snapped to a grid cell):

```r
cell_map <- pts |>
  fgroup_by(cell) |>
  fsummarise(n = GRPN(), value = fmean(value, w = pop),
             geometry = st_union(geometry))
```

`between()` is data.table's and works on any vector — it is both faster and
clearer than `lon >= -20 & lon <= 53`.

## Matrices and input-output tables

Matrices are collapse and kit territory; do not convert them to data.tables.
The one data.table function that helps is `transpose()`, and only for **lists
and data frames** — for a matrix use `t()`.

```r
# aggregate a square IO matrix in both directions
Z_agg <- Z |> fsum(g_rows) |> t() |> fsum(g_cols) |> t()

# row-wise extremes across a set of matrix columns
prange(m[, 1], m[, 2], m[, 3])

# distinct rows of a matrix — kit only, collapse errors on matrices
kit::funique(coords)
```

The full IO toolkit (technical coefficients, Leontief inverse, `%r*%`/`%c*%`,
chained `set = TRUE` scaling, IPF/RAS balancing) is in the `collapse-r` skill's
recipes — it is pure collapse and is documented there.

## Wide correlation tables

A pattern that recurs whenever a table has to go into a paper: compute a
correlation matrix per group inside data.table's `by`, then pull out the
sub-block you want with magrittr's `extract`:

```r
cor_by_country <- d[Year < 2020,
                    qDF(pwcor(.SD, N = TRUE), "variable"),
                    by = .(region, country), .SDcols = vars]

d |>
  num_vars() |>
  pwcor(P = TRUE) |>
  extract(.c(PCGDP_G, INFL), .c(TOT, FDI, REM), ) |>
  print(digits = 3, return = TRUE) |>
  xtable::xtable()
```

`extract(i, j, )` is magrittr's alias for `[i, j, ]` — the trailing comma keeps
the matrix two-dimensional. `pwcor(..., return = TRUE)` in `print` gives you the
formatted character matrix to hand to `xtable`.

`qDF(x, "variable")` turns the matrix into a data frame with the row names in a
column, which is what data.table's `j` needs (a list, not a matrix).
