---
name: scientific-graphics-r
description: >-
  Create publication-quality scientific figures in R for academic papers and
  reports: ggplot2 charts (bar, time-series/line, scatter, stacked/area, facet),
  tmap v4 choropleth maps, pheatmap heatmaps, migest chord/flow diagrams, and
  igraph networks — all in a consistent "house style" built on a pretty_plot()
  theme (theme_bw, black panel border, long outward axis ticks, clean breaks,
  deliberate palettes, vector-PDF output via pdf()/dev.off()).
  Use this skill WHENEVER the user is making any plot, chart, map, heatmap,
  flow/chord/Sankey diagram, network, or figure in R, asks for the pretty_plot
  theme or a consistent figure style, mentions ggplot2/tmap/pheatmap/migest,
  needs a colour palette (viridis/turbo/rainbow/brewer), is porting old tmap v3
  map code to v4, or wants figures saved as PDF for LaTeX — even if they just say
  "plot/map/visualize X in R" without naming a package. Prefer this over ad-hoc
  ggplot so figures match the established style.
---

# Scientific Graphics in R

This skill encodes a specific, battle-tested house style for figures that go
into economics/policy papers and World Bank reports. The goal every time: a
clean **vector PDF**, sized for a LaTeX column, that looks deliberate — black
framed panel, long outward ticks, ~7 axis breaks, formatted labels, a
restrained palette, and categories ordered by magnitude rather than alphabet.

The aesthetic is the point. Default ggplot/tmap output looks generic; the
recipes here are what make a figure look like it belongs in a published paper.
When in doubt, **match the existing figures in the project** — read a nearby
plotting script first and mirror its choices.

## Always start here

Every plotting script begins by loading the shared theme + palette helpers:

```r
source("<path-to-skill>/scripts/pretty_plot.R")   # pretty_plot(), rotate_x(),
        # rainbow_sec(), rainbow_ramp(), vc_terms(), ylorrd(), turbo_clip(),
        # tm_map_layout()
```

If the project already defines `pretty_plot()` (e.g. in its own `helpers.R`),
source that instead — don't redefine it. The bundled copy exists so the style
works in any project, including ones without the original `helpers.R`.

`pretty_plot(lp = "top")` returns a theme; add it to any ggplot. `lp` moves the
legend (`"top"`/`"right"`/`"bottom"`/`"none"`).

**Data verbs.** The recipes below shape data with **collapse** in dplyr-style
(`mutate`, `subset`, `group_by`, `summarise`, `pivot`). Those names are NOT
available from a bare `library(collapse)`/`library(fastverse)` — you must enable
the mask first, exactly as the project scripts do:

```r
library(fastverse)                                   # or library(collapse)
set_collapse(mask = c("manip", "helper", "special")) # enables mutate/subset/...
```

Without that line, use collapse's always-exported `f`-prefixed verbs instead
(`fmutate`, `fsubset`, `fgroup_by`, `fsummarise`; `roworder`/`collap`/`pivot`/
`qF`/`join` are exported regardless). The ggplot/tmap/pheatmap layer is identical
no matter how you shape the data — base R or dplyr work just as well.

## What are you making? (routing)

| You're plotting…                                  | Go to |
|---------------------------------------------------|-------|
| bars, time series/lines, scatter, area, facets    | **Core ggplot recipe** below, then `references/ggplot-cookbook.md` (one section per chart type) |
| choosing/combining colours for any figure         | `references/colours-and-palettes.md` |
| a choropleth / map of countries                   | `references/maps-tmap.md` (tmap **v4** API) |
| a matrix as a colour grid with numbers in cells   | `references/heatmaps-pheatmap.md` |
| flows between regions (chord diagram)             | `references/flows-networks.md` (migest) |
| a directed trade/value network                    | `references/flows-networks.md` (igraph) |
| a LaTeX table, or shaping data to feed a plot      | `references/data-and-tables.md` |

Read the relevant reference file before writing code for that figure type —
each has the exact, version-correct idioms and gotchas.

## Core ggplot recipe

The canonical figure is a bar/point chart of a quantity across countries or
sectors. The conventions below appear on nearly every plot; internalize them.

```r
library(ggplot2)
p <- DATA |>
  # 1. order categories by magnitude, then LOCK the order with a factor
  roworder(-value) |>
  mutate(country = qF(country, sort = FALSE)) |>     # qF keeps current order
  ggplot(aes(x = country, y = value, fill = group)) +
    geom_bar(stat = "identity", position = "stack") +  # or "fill" / position_dodge(0.9)
    # 2. ~7 breaks, formatted labels, bars sitting ON the axis (expand lower = 0)
    scale_y_continuous(n.breaks = 7,
                       expand = expansion(mult = c(0, 0.03)),
                       labels = scales::percent) +     # or label_currency(suffix=" B")
    # 3. a deliberate, ordered palette (see colours reference)
    scale_fill_manual(values = vc_terms(5)) +
    labs(x = NULL, y = "Share of gross exports", fill = "Term") +
    # 4. the theme, then rotate x labels when they are many short codes
    pretty_plot("right") +
    rotate_x()

# 5. save as vector PDF with the device idiom (NOT ggsave) -- print() is required
pdf("figures/.../name.pdf", width = 10, height = 4)   # inches
print(p)
dev.off()
```

The five numbered ideas are the load-bearing ones:

1. **Order by value, lock with a factor.** Readers should see rank instantly.
   Sort (`roworder(-value)`), then make the discrete axis variable a factor with
   `qF(x, sort = FALSE)` (collapse) or `factor(x, levels = unique(x))` so ggplot
   doesn't re-alphabetize.
2. **Anchor bars to the axis.** Bars/stacked areas look wrong floating above the
   x axis. Use `expand = c(0, 0)` (flush) or `expansion(mult = c(0, 0.03))` (tiny
   headroom; `c(0, 0.15)` if you add value labels above bars). Lines/points keep
   the default expand.
3. **~7 breaks and formatted labels** via `scale_*_continuous(n.breaks = 7, …)`
   and `scales::percent` / `scales::label_currency(suffix = " B", scale = 1e-3)`
   / `scales::dollar`. Never show raw `1e+09`.
4. **`pretty_plot()` last**, then `rotate_x()` when the x axis holds many ISO3 or
   sector codes (rotates to vertical, `angle = 270, hjust = 0, vjust = 0.5`).
5. **Save with `pdf(); print(p); dev.off()`** (see "Saving" below).

Two polish details that matter:
- **Pick the unit so axis numbers read O(1–1000), not fractions.** Values in the
  hundreds of millions → keep `$M` (`scales::label_currency(suffix = "M")`);
  don't convert to `0.20 B`. Switch to `B`/`T` only once `M` numbers exceed ~1000.
- **Don't outline bars.** Leave `geom_bar()`/`geom_col()` with no `colour=` (the
  fill alone separates segments); a black outline around every bar reads as
  clutter.

Full per-chart-type recipes (bar, time-series/line, scatter, stacked/area,
facets, log axes, value labels) are in `references/ggplot-cookbook.md`.

## Colour (summary — full guide in `references/colours-and-palettes.md`)

Pick the palette by what the categories *are*, not by counting them:

- **2–4 contrasting flows/directions** (Africa vs ROW, Imports vs Exports): a
  few hand-picked names (`c("orange", "dodgerblue4")`) or
  `scale_*_brewer(palette = "Paired", direction = -1)` / `"Set1"`.
- **Ordered decomposition** (value-chain terms domestic→foreign): `vc_terms(5)`.
- **~10–12 sectors, distinct hues**: `rainbow_sec(11)` — `rainbow()` with the
  too-light pure green swapped for a readable deep green. Append a category with
  `rainbow_sec(11, extra = "#000000")`.
- **Arbitrary n from that same rainbow**: `rainbow_ramp(n)` interpolates the
  corrected rainbow into a `colorRampPalette` so any number of colours stays
  on-brand.
- **Sequential / continuous**: `ylorrd()` (heatmaps), `viridisLite::inferno/
  magma/viridis(n)` for maps, or `turbo_clip(n)` (turbo with its dark ends
  clipped) for high-contrast continuous fills.

Keep the same variable mapped to the same colour across a figure set — if
"Africa" is orange in one plot, keep it orange everywhere.

## Legend placement

Match legend position to how big the legend is:

- **ggplot — `pretty_plot("top")` (default)** when items are **few and short**
  (2–4 flows): a single top row keeps the panel wide. Force one row with
  `guides(fill = guide_legend(nrow = 1))`.
- **ggplot — `pretty_plot("right")`** when items are **many or have long labels**
  (sectors, countries): a right-hand column won't overflow. Use
  `guides(... = guide_legend(ncol = 1))` for a tall list, and pull a wide legend
  in with `theme(legend.margin = margin(l = -200))`.
- **tmap maps — legend INSIDE the map** (oceans/corners are empty space; never
  spend a margin on it). `tm_map_layout()` places it bottom-left; override with
  `tm_legend(position = tm_pos_in("right", "bottom"))`.

## Line-wrapping long labels

Long axis/legend/title text should wrap rather than overflow or shrink the panel:

- Wrap axis tick labels: `scale_x_discrete(labels = scales::label_wrap(15))` or
  pre-wrap with `stringr::str_wrap(x, width = 15)`.
- Compose multi-line labels manually with `\n` (the house idiom for "name +
  count/code"): `paste0(sector, "\n(", code, ")")`.
- Wrap a long legend title or plot title the same way (`\n` or `str_wrap`).

## Saving — always vector PDF via the device idiom

Figures are for LaTeX → **PDF**, dimensions in **inches**, tuned per figure. Use
the graphics-device idiom for **everything**:

```r
pdf("figures/.../name.pdf", width = W, height = H)
print(p)        # REQUIRED for ggplot AND tmap objects inside a script/loop/fn
dev.off()
```

- **base graphics / migest / igraph** draw directly between `pdf()` and
  `dev.off()` — no `print()` needed.
- **pheatmap** also draws to the open device (no `print()`); see its reference.
- **Avoid `ggsave()` and `dev.copy()`.** `ggsave()` re-renders through a separate
  path and `dev.copy()` is fragile in scripts (it copies whatever happens to be
  on screen). The explicit `pdf()`/`dev.off()` pair is predictable and is the
  house standard.
- Forgetting `print()` on a ggplot/tmap object inside `pdf()` → a blank PDF. This
  is the #1 bug with this idiom.

Typical sizes: `6×4` single panel · `10×4` many countries on x · `4.5×4.5`
square heatmap · `8×8` map or chord · `10×6` faceted grid. Start there, adjust.
Create the output dir if missing: `dir.create(..., recursive = TRUE,
showWarnings = FALSE)`.

## Notes on versions

Recipes target **current** packages: ggplot2 ≥ 4.0 (use `linewidth`, not `size`,
for line/border widths) and **tmap ≥ 4** (`fill=` / `fill.scale=` /
`fill.legend=`). Old project code may use **tmap v3** (`tm_polygons(col=,
palette=, style=)`) — it still renders under v4 but emits migration messages;
port it per `references/maps-tmap.md`.

Data wrangling uses **fastverse/collapse** (`|> mutate()`, `fsum`, `pivot`, `qF`,
`collap`, `join`). The plotting layer is identical no matter how you shape the
data; `references/data-and-tables.md` covers the collapse idioms used to get data
into plot-ready shape.
