# Data shaping (collapse/fastverse) and LaTeX tables (xtable)

The plots in this style are fed by **fastverse/collapse** pipelines. You don't
need collapse to make the figures — any tool that produces the right shape works
— but these are the idioms used throughout the projects, so recognizing them
lets you extend existing scripts seamlessly. The base/tidyverse equivalent in
spirit is noted where it helps.

## Setup line you'll see at the top of scripts

```r
library(fastverse)
fastverse_extend(qs, readxl, ggplot2, ...)             # attach extra pkgs
set_collapse(mask = c("manip", "helper", "special"), nthreads = 2)
fastverse_conflicts()
```
`mask = "manip"` makes collapse's fast functions shadow dplyr-named verbs
(`mutate`, `subset`/`filter`, `group_by`, `summarise`), so pipelines read like
dplyr but run on collapse internals.

## Getting data plot-ready

### Long format for fill/dodge/colour aesthetics
ggplot wants one row per (x, series). `pivot()` (collapse) reshapes wide→long;
the new columns are `variable` (names) and `value`.

```r
# wide: country, NDAVAX, REF, DDC, FVA, FDC  ->  long: country, variable, value
WIDE |> pivot("country")                      # ids kept; everything else melted
WIDE |> pivot(ids = c("country", "label"), values = .c(E2R, I2E))
```
The reshaped name/value columns are called `variable`/`value`. To rename them,
`names`/`values` take a **named list**, not a bare string — `pivot("country",
names = list(variable = "term"))` (not `names = "term"`, which selects rather
than renames).
Wide→one-value reshape for matrices (e.g. for pheatmap/maps): `how = "w"`:
```r
LONG |> pivot(ids = "sector_code", values = "NDAVAX", names = "REC", how = "w")
```
(tidyr equivalents: `pivot_longer()` / `pivot_wider()`.)

### Order categories, then LOCK the order
The single most important prep step for ranked bar/point charts:
```r
DATA |>
  roworder(-value) |>                          # sort (data.table::setorder)
  mutate(x = qF(x, sort = FALSE))              # factor in CURRENT order
```
`qF(x, sort = FALSE)` = "make a factor, keep the order the rows are in". Without
it ggplot alphabetizes the axis and the ranking is lost. Base equivalent:
`factor(x, levels = unique(x))` after sorting.

### Aggregate
```r
group_by(DATA, region, year) |> select(EX = value) |> fsum()   # sum by group
collap(DATA, value ~ region + sector, fmean)                   # formula form
```

### Shares within a group (no extra join)
`TRA = "/"` divides each value by its group total in one pass:
```r
mutate(share = fsum(value, list(region, year), TRA = "/"))     # value / group sum
```

### Relabel factor levels for nice axis/legend text
```r
mutate(variable = set_attr(variable, "levels",
        c("Intra-African", "Africa-ROW")))    # rename in place
# or the helper rename_levels(x, OLD = "New", ...) from the project helpers.R
```

### Matrix for heatmap/map colouring
```r
qM(DF, 1)         # data.frame -> numeric matrix, first column -> rownames
```

## LaTeX tables with xtable

Tables go into the same papers as the figures; the convention is **booktabs**,
no row names.

```r
library(xtable)
TABLE |>
  xtable(digits = 1) |>
  print(include.rownames = FALSE, booktabs = TRUE)
```

### "value (share%)" composite cells
A recurring pattern: each cell shows a magnitude plus its share(s) in
parentheses, formatted as a string, before pivoting to wide and printing.

```r
DATA |>
  mutate(res = paste0(round(value, 2), " (", signif(share * 100, 2), "%|",
                      signif(reg_share * 100, 2), "%)")) |>
  pivot("sector_code", "res", "rec_o", how = "w") |>
  xtable() |> print(include.rownames = FALSE, booktabs = TRUE)
```

### Add a Total column / format every numeric column as a share
```r
TBL |>
  (\(d) add_vars(d, Total = psum(num_vars(d))))() |>
  colorder(id, Total) |>
  transformv(is.numeric, \(x) paste0(signif(round(x, 2), 4), " (",
                                     signif(proportions(x) * 100, 2), "%)")) |>
  xtable(digits = 1) |> print(include.rownames = FALSE, booktabs = TRUE)
```

### Notes
- `print.xtable()` writes LaTeX to the console; redirect with `print(..., file =
  "tables/x.tex")` to save, or copy into the paper.
- `booktabs = TRUE` requires `\usepackage{booktabs}` in the LaTeX preamble.
- Pre-format numbers as strings (`signif`, `round`, `paste0`) when you need
  composite cells; otherwise let `xtable(digits = …)` handle rounding.
