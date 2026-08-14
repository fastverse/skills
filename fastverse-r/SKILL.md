---
name: fastverse-r
description: >-
  Expert guidance for the fastverse in R — the high-performance suite built on
  data.table, collapse, kit and magrittr, loaded with library(fastverse).
  Covers how the loader itself works (fastverse_extend/detach/reset/sitrep/
  update/child, .fastverse project config files, options, OpenMP threading
  across the three multithreaded packages), the kit API (psum/pmean/pfirst/
  plast/fpmin/fpmax/prange/pany/pall/pcount parallel statistical functions,
  vswitch/nswitch vectorized and nested switches, iif/nif, topn, charToFact,
  countOccur, uniqLen, setlevels, psort), the data.table API ([i, j, by],
  := and set() reference updates, .SD/.N/.I/.GRP/.BY, GForce, froll* rolling
  functions, keyed/rolling/non-equi joins and foverlaps, fread/fwrite, set*
  helpers, copy/rowid/rleid/setattr/transpose/nafill/shift), the magrittr
  operators (%>%, %<>%, %$%, %T>%, extract, set_names), and above all HOW THE
  FOUR PACKAGES DIVIDE THE WORK — when to reach for collapse versus
  data.table versus kit, with measured timings.
  Use this skill WHENEVER the user is writing or reviewing R code that loads
  the fastverse, data.table, collapse or kit; whenever they mention fastverse,
  data.table, kit, magrittr, .fastverse files, fastverse_extend, setDTthreads,
  kit.nThread, DT[i, j, by], :=, .SD, GForce, frollmean/frollapply, rolling or
  non-equi joins, fread/fwrite, psum/pmean/topn/vswitch/nswitch/iif/nif; and
  whenever they ask which of these packages to use for a task, how to combine
  them, or how to speed up an R data pipeline. Also use it when translating
  dplyr/base R/pandas code to a fast R stack, when a script mixes data.table
  and collapse, and when working with large data, panels, matrices, or
  spatial (sf) data frames in R.
  REQUIRES the companion skill collapse-r, which documents the collapse API
  itself. This skill deliberately does not duplicate it: it covers the other
  three packages, the loader, and the division of labour between all four.
  Load collapse-r alongside this one and delegate to it for anything that
  turns on how a collapse function behaves.
---

# The fastverse

`library(fastverse)` attaches four packages that were chosen to work together:

| Package | Version tested | What it is for |
|---|---|---|
| **data.table** | 1.18.4 | The `[i, j, by]` query engine, reference updates, rolling windows, rolling/non-equi joins, fast file I/O |
| **collapse** | 2.1.7 | Class-agnostic statistical computing: grouped/weighted statistics, transformations, joins, reshaping, panels |
| **kit** | 0.0.21 | Row-wise ("parallel") statistics across vectors, vectorized switches, `topn` |
| **magrittr** | 2.0.5 | `%>%`, `%<>%`, `%$%`, `%T>%` and the function aliases |

Jointly they depend only on base R and Rcpp. That is the point: you get a
complete high-performance stack without a dependency tree.

## Load collapse-r alongside this skill

collapse is where most of the actual work happens, and **this skill deliberately
does not document it.** The companion skill **`collapse-r`** does, in depth. The
two are meant to be used together; on its own this one is a map with the largest
territory left blank.

**Delegate to `collapse-r` whenever the answer turns on how a collapse function
behaves.** Concretely, go there for:

| Topic | Where |
|---|---|
| Fast Statistical Functions, `g`/`w`/`TRA`/`set` arguments | `collapse-r` → `references/statistical-functions.md` |
| `fsubset`/`fselect`/`fmutate`/`fsummarise`/`across`/`fslice`/`roworder` signatures | → `references/data-manipulation.md` |
| `join()`, `pivot()`, `collap()`, `rowbind()` arguments and semantics | → `references/join-pivot-aggregate.md` |
| `flag`/`fdiff`/`fgrowth`/`fcumsum`, `t =`, indexed frames, `psmat` | → `references/time-series-panel.md` |
| `GRP`/`qF`/`qG`/`group`/`gsplit`, using collapse inside a package | → `references/programming.md` |
| `setv`/`copyv`/`setop`/`%+=%`/`settransform`, by-reference computing | → `references/efficiency.md` |
| `sort`/`na.rm`/`nthreads`, `set_collapse()`, namespace masking | → `references/efficiency.md`, `gotchas.md` |
| `qsu`/`descr`/`qtab`/`pwcor`, `rsplit`/`unlist2d`, labels | → `references/summaries-and-lists.md` |
| Any collapse pitfall or surprising behaviour | → `references/gotchas.md` |

What stays here: **data.table**, **kit**, **magrittr**, the **loader**, and —
most importantly — **the division of labour between all four**. Where this skill
does show collapse code, it is to illustrate a cross-package choice, not to
document the function; check `collapse-r` before relying on an argument you see
used here.

## Table of contents

- [Load collapse-r alongside this skill](#load-collapse-r-alongside-this-skill)
- [The division of labour](#the-division-of-labour) ← start here
- [House style](#house-style)
- [Loading and configuring](#loading-and-configuring)
- [Threading](#threading)
- [The top interop traps](#the-top-interop-traps)
- [Reference files](#reference-files)

## The division of labour

Most tasks can be written three ways. Choosing well is the single highest-value
thing this skill teaches, so the rules below are ordered by how often they
decide something.

### Default to collapse

collapse is the default for data manipulation because it is class-agnostic (the
same call works on a `data.frame`, `data.table`, `tbl_df`, `sf` object, matrix
or plain vector, and gives back what you gave it), because its verbs compose,
and because it is usually at least as fast. Concretely, prefer:

| Task | Use | Not | Measured |
|---|---|---|---|
| Join two tables | `join()` | `merge()`, `X[Y, on=]` | 69 ms vs 101 ms (2M × 100k left join) |
| Reshape long ↔ wide | `pivot()` | `melt()`, `dcast()` | wider: **8 ms vs 127 ms** (2M → 500k × 4) |
| Distinct rows | `funique()` | `unique()`, `kit::funique()` | 35 / 40 / 57 ms (2M × 2) |
| Stack tables | `rowbind()` | `rbindlist()` | 9 ms vs 19 ms (50 × 100k) |
| Drop unused levels | `fdroplevels()` | `data.table::fdroplevels()` | collapse wins; also class-agnostic |
| Order rows | `roworder()`, `roworderv()` | `setorder()` | comparable; `roworder` works on any frame |
| Count / tabulate | `fcount()`, `qtab()` | `.N` by group, `table()` | comparable, richer output |
| Grouped aggregation, no filter | `fgroup_by() \|> fsummarise()` or `collap()` | `[, .(...), by=]` | 12 ms vs 21 ms (3 stats, 5M × 10k groups) |
| Grouped aggregation **with a filter** | `d[i, j, by]` | a collapse pipeline | 8 ms vs 13 ms — the one clear data.table win |

`join()` earns its place on more than speed. It prints a one-line match report,
and it can *check* the join:

```r
join(x, y, on = "id", how = "left")
# left join: x[id] 3/4 (75%) <1.5:1st> y[id] 2/3 (66.7%)

join(x, y, on = "id", how = "left", validate = "m:1")   # errors if y is not unique
join(x, y, on = "id", how = "full", column = TRUE)      # adds a .join indicator
```

`merge()` gives you none of that, and it **sorts the result and sets a key** —
`join()` preserves `x`'s row order. Silent reordering is a common source of bugs
when a downstream step assumes positional alignment.

### Reach for data.table when

**1. The query is a genuine `[i, j, by]`.** When you filter, aggregate and group
in one step, data.table fuses them — it never materializes the filtered
intermediate, and the grouped aggregation runs through GForce:

```r
d[id == "a", .(b = sum(c)), by = g]                                   #  8 ms
d |> fsubset(id == "a") |> fgroup_by(g, sort = FALSE) |>
     fsummarise(b = fsum(c, na.rm = FALSE))                           # 13 ms
```

This is data.table's home turf, and the *filter* is what earns it — see the
grouped-aggregation numbers below, where collapse wins once the filter is gone.
Write it in the compact form; that *is* the idiom.

**Comparing the two fairly requires matching two defaults.** `by = g` returns
groups in first-appearance order, whereas `fgroup_by(g)` sorts (`keyby = g` is
the sorted data.table equivalent). And `sum`/`mean` default to `na.rm = FALSE`
while every collapse Fast Statistical Function defaults to `TRUE`. Unmatched,
you are timing a sort and a missing-value scan that the other side never ran —
and getting different answers on data with `NA`s.

**2. You are updating columns by reference.** `:=` adds or modifies columns
without copying the table, and it takes an `i` so you can update a subset:

```r
d[, area_km2 := area / 1e6]
d[source == "OSM", weight := 1 + log(value + 1)]
for (j in cols) set(d, j = j, value = d[[j]] * 2)     # loop form, no [.data.table overhead
```

collapse's `settransform()`/`setv()`/`%+=%` do the unconditional case equally
well (3 ms vs 4 ms), so this rule is really about the **conditional** update:
`d[i, col := value]` has no clean collapse equivalent.

**3. Rolling windows.** collapse has no rolling functions at all.

```r
frollmean(x, 10)                       # also frollsum/min/max/prod/sd/var/median
frollapply(x, 10, mad, na.rm = TRUE)   # arbitrary function
frollmean(x, n, adaptive = TRUE)       # per-observation window widths
```

**4. Rolling and non-equi joins**, `foverlaps()`, and keyed binary search.
`join()` covers equi-joins only.

**5. Functions that simply do not exist elsewhere**: `copy()`, `rowid()`,
`rleid()`, `setattr()`, `nafill()`, `shift()` with `type = "cyclic"`,
`transpose()`, `fread()`/`fwrite()`, `CJ()`, `between()`/`inrange()`,
`tstrsplit()`, `fcoalesce()`.

### Reach for kit when

kit's unique contribution is **row-wise statistics across several vectors** —
collapse aggregates *down* columns, kit aggregates *across* them:

```r
psum(a, b, c, na.rm = TRUE)     # 7 ms vs rowSums(cbind(...)) 23 ms on 5M x 3
pmean(a, b, c)                  # also pprod, fpmin, fpmax, prange
pfirst(a, b, c)                 # first non-missing — coalesce
pany(x, y)  pall(x, y)          # logical
pcountNA(a, b, c)               # how many NA per row
```

No matrix is built, and they take a `data.frame` directly: `psum(d[, cols])`.

Also uniquely kit's:

```r
topn(x, 10)                         # indices of the 10 largest — 5 ms vs order() 115 ms
vswitch(x, values, outputs, default = x)      # 1:1 recode, ~3x faster than fcase
nswitch(x, v1, o1, v2, o2, default = x)       # same, inline pairs
```

Everything else in kit has a collapse counterpart — `funique`/`funique`,
`uniqLen`/`fndistinct`, `countOccur`/`fcount`, `charToFact`/`qF`,
`count(x, v)`/`whichv`, `countNA`/`fnobs` — at timings within noise of each
other, so **prefer the collapse version** for consistency and because it takes
groups and weights. (`count(x, v)` is the one clear loss: 23 ms against 1 ms for
`length(whichv(x, v))`.) Two exceptions where kit wins: `kit::funique()` handles
**matrices**, which collapse's errors on, and `countNA()` on a *list* returns a
per-element count rather than a total.

### Reach for magrittr when the base pipe cannot do it

Use `|>` by default. Switch to magrittr for what it alone provides:

```r
d %<>% fsubset(v > 1)                        # update in place
d %$% fmean(v, g)                            # expose columns as variables
d %T>% (\(x) cat(nrow(x), "\n")) %>% nrow()  # tee
cols %>% fselect(d, .)                       # . in a non-first position
```

`extract()` is the alias that lets a data.table query live in a pipe — it works
with the base pipe too, which matters because `d |> [...]` is not valid R:

```r
d |> extract(v > 1, .(m = sum(v)), by = g)
d |> extract(j = .SD[topn(v, 1)], by = g)    # top row per group
```

### Do not convert objects just to use data.table

This is the rule most often broken. An `sf` data frame, a matrix, a tibble, a
`pdata.frame` — all of these can be manipulated directly with collapse and kit.
Converting to a data.table to run one query, then converting back, costs copies
and silently drops class-specific attributes (`sf` loses its geometry column
handling and CRS through a careless round-trip).

```r
# NO — destroys and rebuilds the sf object
qDT(pts) |> extract(, .(area = sum(area)), by = cat) |> st_as_sf()

# YES — row-preserving verbs keep the sf class, geometry and CRS intact
pts |> fsubset(area > 1e3) |> fmutate(area_km2 = area / 1e6)
```

**Row-preserving** verbs (`fsubset`, `fmutate`, `fselect`, `roworder`, `join`)
round-trip `sf` correctly. When a verb **reduces rows**, you have to say what
happens to the geometry — either aggregate it too, or set it aside first:

```r
# aggregate it — st_union() dissolves, ffirst() keeps a representative
pts |> fgroup_by(cat) |> fsummarise(n = GRPN(), geometry = st_union(geometry))
pts |> fgroup_by(cat) |> fsummarise(n = GRPN(), geometry = ffirst(geometry))

# or set it aside — convert at the START of the aggregation pipeline
pts |> qDT() |> fgroup_by(cat) |> fsummarise(n = GRPN(), area = fsum(area))
```

Both give a working result. `st_union` returns a valid `sf` with the CRS intact;
`qDF()`/`qDT()`/`qTBL()` drop the `sf` class but **keep** the geometry as an
`sfc` list column, so nothing is thrown away and `st_as_sf()` restores it later.

Do neither and it fails silently: `fsummarise`/`collap` drop the geometry while
leaving the `sf` class and its `sf_column` attribute pointing at nothing, so the
result throws `attr(obj, "sf_column") does not point to a geometry column` the
first time you print it. `fcount()` on an `sf` object errors outright
(`Unsupported types: character and list`) — `qDT()` first.

data.table does export a few genuinely class-agnostic functions — `transpose()`
(lists and data frames), `fifelse()`, `fcase()`, `fcoalesce()`, `frollmean()`
and friends, `nafill()`, `shift()`, `between()` — and those are fine to call on
anything. It is `setDT()`/`as.data.table()` that you should not reach for
reflexively.

## House style

The `collapse-r` skill sets the style for collapse code: **full function names,
piped, one verb per line, no shorthand aliases** (`fselect` not `slt`, `fsubset`
not `sbt`). That carries over here. Two additions:

**data.table's compact form is not shorthand — keep it compact.** `d[i, j, by]`
is one fused operation; splitting it into three piped steps changes what runs.
Write `d[id == "a", .(b = sum(c)), by = g]`, not a pipeline.

**Do not mix idioms inside one expression.** A pipeline that is mostly collapse
verbs should not have a bare `[` in the middle of it; either use `extract()` so
it reads as a pipe stage, or break the pipeline. Mixed code is hard to review
because the reader has to track which package's semantics apply to each line.

**Do not set global options on the user's behalf.** `setDTthreads()`,
`options(kit.nThread=)`, `set_collapse()` and `options(datatable.*)` are all
session-wide and affect every later call — including other people's code in the
same session. Set them only when the user asks, when you are writing a new
script's header, or when you are matching a convention the project already has.

**Keep the pipeline minimal — these are large datasets.** Every named
intermediate is a full copy that stays in memory until something overwrites it,
and every extra grouped pass re-derives a grouping that was already computed.
Four habits, in rough order of how much they save:

- **One grouped `fmutate` per grouping, not several.** Later expressions in the
  same call see columns created by earlier ones, so a lag and the rolling
  statistic computed from it belong in one call, not two.
- **Feed expressions straight into the function that consumes them** rather than
  binding them to a name first — `join(d[, .(...), by = g], d, …)`, not
  `grid <- d[, .(...), by = g]` followed by `join(grid, d, …)`.
- **Overwrite, or `rm()`.** A chain that leaves `d_pad`, `d_real` and `d_final`
  alive has three copies of the data resident; usually only the last is wanted.
- **Ask for the least the call can give you.** `fgroup_by(g, return.groups = FALSE)`
  when the group labels are never read back, `fsubset(d, cond, only, needed, cols)`
  rather than filtering wide and selecting later.

The efficiency of a single call matters much less than not doing the work twice.

**Drop a guard once you have made it unnecessary — do not keep it "for safety".**
The tempting move after restructuring data is to leave the old protection in
place. It is not free, and it is not neutral: a reader takes the guard as
evidence that the hazard is still live. The clearest case is `t =` on a panel you
have just padded to a complete grid — position and calendar now coincide, so
`fgrowth(PCGDP, t = Year)` returns *exactly* what `fgrowth(PCGDP)` returns, at
3.25× the cost, while telling the next reader the panel is still irregular. Same
for `na.rm = TRUE` on a column you just filtered to completeness, or `funique()`
after a `validate = "1:1"` join. Guard where the hazard is, then let it go.

## Loading and configuring

```r
library(fastverse)     # attaches data.table, magrittr, kit, collapse (in that order)
```

The attachment order matters and is deliberate: **collapse is attached last**,
so `collapse::funique`, `collapse::fduplicated` and `collapse::fdroplevels` mask
the `kit` and `data.table` functions of the same name. These three clashes are
suppressed from the conflict report on purpose — the collapse versions are the
intended winners. Everything else is reported:

```r
fastverse_conflicts()
# x data.table::%notin%() masks base::%notin%()
```

Add packages for the session, and see their versions and conflicts as they load:

```r
fastverse_extend(sf, s2, fixest)
fastverse_extend(qs2, sf, units, tmap, install = TRUE)   # install anything missing first
```

For a project, put a `.fastverse` file (no extension) in the project root. This
is the preferred way to pin a project's stack — it is read by `library(fastverse)`,
it sets options before *and* after attaching, and it is version-controlled with
the project:

```
_opt_fastverse.install = TRUE
_env_ARMA_64BIT_WORD = TRUE

magrittr, sf, data.table, kit, collapse, ggplot2, fixest, qs

_opt_max.print = 100
```

Packages attach in file order, so keep `collapse` after `kit` and `data.table`
unless you specifically want the other masking.

`references/setup.md` has the rest: `fastverse_detach`, `fastverse_reset`,
`fastverse_sitrep`, `fastverse_update`, `fastverse_child`, and the four
`fastverse.*` options.

## Threading

Three of the four packages multithread, and each has its own control:

```r
setDTthreads(4)                    # data.table   — getDTthreads()
set_collapse(nthreads = 4)         # collapse     — get_collapse("nthreads")
options(kit.nThread = 4L)          # kit          — note the L, see below
```

Two things to know before touching them:

**Nesting multithreaded calls oversubscribes the CPU.** A multithreaded collapse
or kit function called inside a data.table `by=` (which is itself parallel over
groups) will usually be *slower* than the single-threaded version, not faster.
Keep the inner call single-threaded.

**On macOS, CRAN binaries of collapse and kit ship without OpenMP.** kit tells
you at attach time — `Attaching kit 0.0.21 (OPENMP disabled using 1 thread)` —
and setting `kit.nThread` then does nothing at all. data.table bundles its own
OpenMP and is unaffected. If a threading change makes no difference, check this
before looking anywhere else.

## The top interop traps

Full list in `references/interop.md`; these are the ones that bite most often.

**Inside `by=`, use `lapply(.SD, mean)` — not a collapse function.** GForce only
recognises the base names, so substituting the "fast" one costs 19×. But the
native collapse route is both clearer and, matched like-for-like, faster:

```r
d |> fgroup_by(g, sort = FALSE) |> fselect(x, y, z, w) |> fmean(na.rm = FALSE)  # 31 ms
d[, lapply(.SD, mean), by = g]                                                  # 36 ms
d[, fmean(.SD, drop = FALSE, na.rm = FALSE), by = g]                            # 303 ms
d[, lapply(.SD, fmean, na.rm = FALSE), by = g]                                  # 674 ms
```

All four return identical results including row order. The full ranking, the
sorted variants and the `datatable.verbose` trace are in
`references/interop.md`.

**GForce switches off for composed expressions.** `max(x) - min(x)` in one `j`
expression is not optimized; the two calls have to be separate. collapse has no
such restriction, and beats even the GForce-optimized form here:

```r
d[, .(r  = max(x) - min(x)), by = g]                    # 104 ms — no GForce
d[, .(mx = max(x), mn = min(x)), by = g]                #  43 ms — GForce
d |> fgroup_by(g, sort = FALSE) |>
     fsummarise(r = fmax(x, na.rm = FALSE) -
                    fmin(x, na.rm = FALSE))             #  28 ms
```

**`fsubset()` drops a data.table key; `d[i]` keeps it.** If you rely on the key
downstream, re-`setkey()` or use `[`.

**kit's `nThread` must be an integer.** `charToFact(x, nThread = 4)` and
`psort(x, nThread = 4)` both error on the double; so does
`options(kit.nThread = 4)` for those two functions. Always write `4L`.

**`hasNA` is deprecated in `froll*`** as of data.table 1.17 — use `has.nf`.

## Reference files

Read the one that matches the task rather than guessing at arguments.

- **`references/interop.md`** — the decision rules above in full, with measured
  timings: collapse inside `[i, j, by]`, the five ways to aggregate `.SD` ranked,
  class and key preservation, grouped rolling windows, when converting to
  data.table is and is not worth it.
- **`references/data-table.md`** — the `[i, j, by]` engine, special symbols
  (`.SD`/`.SDcols`/`.N`/`.I`/`.GRP`/`.BY`/`.EACHI`), `:=` and `set()`, GForce
  rules, the `froll*` family, keyed/rolling/non-equi joins and `foverlaps`,
  `fread`/`fwrite`, the `set*` helpers, and data.table's gotchas.
- **`references/kit.md`** — every kit function with its signature, what it beats
  and by how much, and the type/threading rules that trip people up.
- **`references/setup.md`** — the loader: `fastverse_extend`/`detach`/`reset`/
  `sitrep`/`update`/`install`/`child`, `.fastverse` project files, global
  configuration, the four options, and the OpenMP situation in detail.
- **`references/recipes.md`** — worked patterns lifted from production research
  code: grouped rolling statistics, coalescing columns, recoding with
  `vswitch`/`nswitch`, top-N per group, conditional reference updates, reading
  and binding many files, input-output table work, and spatial data frames.

And the other half of the pair, which you should have loaded alongside this one:

- **`collapse-r`** — the entire collapse API, plus its own efficiency guidance
  (minimal grouping, `sort`/`na.rm`/`nthreads`, materializing less, computing by
  reference) and its gotchas list. See the delegation table at the top of this
  file for which of its reference files answers what.

The split to keep in mind: **this skill tells you which package to use;
`collapse-r` tells you how to use collapse correctly.** A question that starts
"which of these should I…" is answered here. A question that starts "what does
this argument do" is answered there. When in doubt, check there too — the cost of
reading one extra reference file is far below the cost of guessing at a
signature.
