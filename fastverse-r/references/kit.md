# kit

kit (0.0.21) is a small C library of things base R does slowly or not at all.
Where a function overlaps with collapse, this file says which to prefer but does
not document the collapse side — use the **`collapse-r`** skill for that.
Three groups matter: **row-wise ("parallel") statistics**, **vectorized
switches**, and **`topn`**. Everything else overlaps with collapse, where the
collapse version is usually the better choice.

Since 0.0.21 kit is maintained by the fastverse team, and `fpmin`, `fpmax`,
`prange` are new in that release.

## Table of contents
- [Parallel (row-wise) statistical functions](#parallel-row-wise-statistical-functions)
- [Vectorized and nested switches](#vectorized-and-nested-switches)
- [iif and nif](#iif-and-nif)
- [topn](#topn)
- [The overlap with collapse](#the-overlap-with-collapse)
- [Gotchas](#gotchas)

## Parallel (row-wise) statistical functions

These are the reason to load kit. collapse aggregates *down* a column; these
aggregate *across* several vectors, element by element, without building a
matrix.

```r
psum(..., na.rm = FALSE)      pprod(..., na.rm = FALSE)     pmean(..., na.rm = FALSE)
fpmin(..., na.rm = FALSE)     fpmax(..., na.rm = FALSE)     prange(..., na.rm = FALSE)
pfirst(...)                   plast(...)                    # na.rm = TRUE, not an argument
pall(..., na.rm = FALSE)      pany(..., na.rm = FALSE)
pallNA(...)                   panyNA(...)
pallv(..., value)             panyv(..., value)
pcount(..., value)            pcountNA(...)
```

`...` is either several vectors of equal length, **or a single list / data
frame** — which is how you apply one across a set of columns:

```r
psum(a, b, c, na.rm = TRUE)
psum(d[, c("x1", "x2", "x3")])          # data.table column subset
d |> fselect(accommodation:waste) |> psum()
```

Measured on 5M × 3 doubles with NAs:

| | kit | alternative | |
|---|---|---|---|
| `psum(a,b,c, na.rm=TRUE)` | 7 ms | `rowSums(cbind(...), na.rm=TRUE)` 23 ms | 3.3× |
| `pmean(a,b,c, na.rm=TRUE)` | 20 ms | `rowMeans(cbind(...))` 26 ms | 1.3× |
| `fpmin(a,b,c)` | 42 ms | `pmin(a,b,c)` 43 ms | ≈ 1× |
| `pfirst(a,b,c)` | 9 ms | `data.table::fcoalesce(a,b,c)` 4 ms | **0.4×** |

Two honest notes from that table. `fpmin`/`fpmax` match `pmin`/`pmax` on speed —
use them for consistency of style and because they refuse to recycle (see
gotchas), not for performance. And `fcoalesce()` beats `pfirst()` for the plain
coalesce case; reach for `pfirst` when you need what `fcoalesce` cannot do —
lists, or factors (all inputs must share levels).

Types: `psum`/`pprod` take integer, logical, double, complex. `pmean`, `fpmin`,
`fpmax`, `prange` take integer, logical, double. `pany`/`pall` take logical only.
All error on factors. `pfirst`/`plast` take any type with a defined `NA`, plus
lists, but cannot mix integer with complex or character with factor.

`prange` returns `max - min` as a double, not a two-element range.

Common uses from research code:

```r
# coalesce a set of alternative columns, keeping the first that is present
d |> fmutate(industrial = pfirst(mining_industrial, industrial), mining_industrial = NULL)
cost_per_edge <- with(edges, pfirst(ug_cost_km, cost_km) * distance / 1000)

# row totals over a block of indicator columns, then filter
d |> fsubset(psum(fselect(d, accommodation:waste)) > 0)

# how many significance thresholds a p-value clears
d |> fmutate(stars = psum(p < 0.01, p < 0.05, p < 0.1))

# rows with any missing among a set of columns
d |> fsubset(panyNA(fselect(d, x1, x2, x3)))
```

## Vectorized and nested switches

`vswitch` maps values to outputs 1:1; `nswitch` is the same thing with the pairs
written inline. Both beat the alternatives clearly:

```r
vswitch(x, values, outputs, default = NULL, nThread = getOption("kit.nThread"), checkEnc = TRUE)
nswitch(x, value1, output1, value2, output2, ..., default = NULL, nThread, checkEnc)
```

On 5M character elements recoding 5 of 9 levels:

| | time |
|---|---|
| `vswitch` | 51 ms |
| `nswitch` | 47 ms |
| `kit::nif` | 112 ms |
| `data.table::fcase` | 161 ms |

`default = x` is the idiom for "leave everything else alone":

```r
# recode ISO codes, leaving unmatched ones untouched
vswitch(x, c("ZAR","TMP","ROM","MNT"), c("COD","TLS","ROU","MNE"), default = x)

# collapse many sector codes into one
nswitch(as.character(sector), "EGW","SRV", "SMH","SRV", "TRA","SRV", "PTE","SRV",
        default = as.character(sector))

# recode a factor cheaply: switch the levels, not the values
levels(f) <- vswitch(levels(f), c("ZAR","TMP"), c("COD","TLS"), default = levels(f))

# lookup-table form, when the mapping lives in a named list
vswitch(x, unlist(sec_map), rep(names(sec_map), lengths(sec_map)), default = x)
```

`outputs` may be a list of full-length vectors rather than scalars, in which case
each match takes the corresponding element from its vector.

Recoding factor **levels** rather than the factor itself (third example above) is
much cheaper on long vectors, and is what production code does.

## iif and nif

```r
iif(test, yes, no, na = NULL, tprom = FALSE, nThread = getOption("kit.nThread"))
nif(..., default = NULL)          # when1, value1, when2, value2, ...
```

`iif` is `ifelse` done properly: it keeps the attributes of `yes` (so `Date` and
factor results survive), and it refuses to silently coerce — `yes` and `no` must
be the same type unless you pass `tprom = TRUE`. `na =` sets the value for `NA`
tests. On 5M doubles it takes 8 ms against `base::ifelse`'s 75 ms.

`data.table::fifelse` does the same job at 6 ms and `fcase` mirrors `nif`. The
differences are semantic, not performance:

- `fifelse` coerces integer to double; `iif` errors unless `tprom = TRUE`.
- `iif`'s `na` defaults to `NULL` (meaning "the NA of `yes`'s type");
  `fifelse`'s defaults to `NA`.
- `nif`'s `default` is `NULL`; `fcase`'s is `NA`.
- `nif` and `iif` are callable from C by other packages.

Either is fine. Pick one per project and stay with it. Both evaluate lazily, so
a branch that would error is never reached if an earlier condition matched.

`nif`'s `default` **must be named** — a trailing unnamed argument is read as
half of a condition/value pair and you get "please supply an even number of
arguments".

## topn

```r
topn(vec, n = 6L, decreasing = TRUE, hasna = TRUE, index = TRUE)
```

`order(vec, decreasing = TRUE)[1:n]` without sorting the other 99.99% of the
vector. On 5M doubles asking for 10: **5 ms vs 115 ms**. Note `decreasing`
defaults to `TRUE` here, the opposite of `base::order`.

It returns indices, which is what makes it compose:

```r
d[topn(value, 10)]                                     # top 10 rows
d |> extract(j = .SD[topn(value, 10)], by = .(outcome, type))   # top 10 per group
d |> ss(topn(psum(abs(nv(d))), 15))                    # collapse subsetting
topn(mdist, 101L, decreasing = FALSE, hasna = FALSE)   # 100 nearest + self
topn(x, 6L, index = FALSE)                             # the values themselves
```

`hasna = FALSE` is a real speed-up when you know there are no `NA`s, and gives
wrong answers if there are. Above roughly `n = 1500`–2000 `topn` falls back to
`order()` internally, so it is for genuinely small `n`.

Numeric and integer input only.

## The overlap with collapse

kit and collapse both provide these. Measured on 5M elements, they are within
noise of each other, so **prefer the collapse version** — consistent naming, and
it takes `g`/`w` arguments:

| kit | collapse | kit | collapse |
|---|---|---|---|
| `funique` | `funique` | 57 ms | 35 ms |
| `uniqLen` | `fndistinct` | 7 ms | 7 ms |
| `countOccur` | `fcount` | 9 ms | 10 ms |
| `charToFact` | `qF` | 12 ms | 14 ms (8 ms with `sort = FALSE`) |
| `count(x, v)` | `length(whichv(x, v))` | 23 ms | **1 ms** |
| `countNA` | `length(x) - fnobs(x)` | 1 ms | ~0 ms |
| `fduplicated` | `fduplicated` | — | — |
| `setlevels` | `setattr(f, "levels", …)` | — | — |

When `library(fastverse)` attaches everything, `funique` and `fduplicated`
resolve to the **collapse** versions, because collapse is attached last. This is
deliberate and the conflict is hidden from `fastverse_conflicts()`.

Three cases where the kit version is the right call:

- **`kit::funique()` works on matrices.** `collapse::funique()` errors with
  "only supports atomic vectors and data.frames". Call it qualified:
  `kit::funique(m)`.
- **`countNA()` on a list** returns the count per element rather than a single
  total, and counts each element against its own type's `NA`.
- **`charToFact()` keeps `NA` as a level** by default (`addNA = TRUE`), matching
  `addNA(as.factor(x))` rather than `as.factor(x)`.

`psort()` is a parallel character sort, documented as experimental. `fpos()`
finds a small matrix inside a larger one. `shareData`/`getData`/`clearData`
share an object between R sessions through a memory map — also experimental.
None of these show up in production code; treat them as available but unproven.

## Gotchas

**1. `setlevels()` modifies by reference.** It has no `set` prefix, but it
behaves like one, so an alias is silently changed too:

```r
x <- factor(c("A","A","B","C"))
y <- x
setlevels(x, new = c("X","Y","Z"))
levels(y)    # "X" "Y" "Z"  — y changed as well
```

`old =` defaults to all levels, so `setlevels(x, new = ...)` replaces the lot
positionally. Naming an `old` level that does not exist is an error unless
`skip_absent = TRUE`.

**2. `nThread` must be an integer for some functions and not others.**
`charToFact` and `psort` reject a double; `vswitch`, `nswitch` and `iif` accept
it. Worse, `options(kit.nThread = 4)` — a double — breaks `charToFact` and
`psort` everywhere in the session. Always write `4L`.

**3. kit's OpenMP is off in CRAN macOS binaries.** It says so on attach:
`Attaching kit 0.0.21 (OPENMP disabled using 1 thread)`. `nThread` is then inert,
and `psum`/`vswitch`/`iif` are single-threaded regardless. To get it, install
OpenMP for macOS and rebuild from source or from r-universe
(`fastverse_install(kit, only.missing = FALSE, repos = .fastverse_repos)`).

**4. The p-functions do not recycle.** Unlike `pmin`/`pmax`, a length-1 argument
is an error, not a broadcast:

```r
psum(1:3, 1L)
# Error: Argument 2 is of length 1 but argument 1 is of length 3.
#        If you wish to 'recycle' your argument, please use rep()
```

This is a feature — it catches a whole class of silent alignment bugs — but it
means you write `psum(x, rep(1L, length(x)))` when you really do want a constant.

**5. `topn`'s `decreasing` defaults to `TRUE`**, the opposite of `base::order`.
`topn(x, 6)` gives the six largest; `order(x)[1:6]` gives the six smallest.

**6. `pfirst`/`plast` have no `na.rm` argument** — they always skip missings,
that being the whole point. They return `NA` only where every input is `NA`.
