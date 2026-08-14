# Colours and palettes

Colour is chosen by **what the categories represent**, not by counting them. The
four families below cover every figure in this style. All helpers come from
`scripts/pretty_plot.R`.

## Decision guide

| Categories are…                                   | Use |
|---------------------------------------------------|-----|
| 2–4 contrasting flows/directions                  | custom named colours, or RColorBrewer `Paired`/`Set1` |
| an ordered decomposition (few ordered parts)      | `vc_terms()` (hand-tuned orange→blue) |
| ~10–12 distinct discrete classes (sectors)        | `rainbow_sec(n)` |
| an arbitrary number of ordered classes            | `rainbow_ramp(n)` |
| a continuous / sequential quantity (maps, heatmaps)| `ylorrd()`, viridis (`inferno`/`magma`/`viridis`), or `turbo_clip()` |

Keep a variable's colour **consistent across a figure set** (if "Africa" is
orange once, keep it orange).

---

## 1. Custom named colours (2–4 contrasts)

For a small number of contrasting series, hand-pick R colour names. The recurring
house choices:

```r
scale_fill_manual(values = c("orange", "dodgerblue4"))         # two flows
scale_colour_manual(values = c("black", "orange"))             # World vs Africa
scale_fill_manual(values = c("red2","orange","yellow2","green2","dodgerblue4","dodgerblue"))
```
Useful names: `orange`, `dodgerblue`, `dodgerblue4`, `green2`, `yellow2`, `red2`,
`gray85`, `gray20`, `lightblue`, `black`. `vc_terms(5)`/`vc_terms(6)` bundles the
ordered orange→blue gradient used for value-chain decompositions.

## 2. RColorBrewer (qualitative & sequential)

```r
scale_colour_brewer(palette = "Set1")                  # up to 9 distinct
scale_fill_brewer(palette = "Paired", direction = -1)  # paired light/dark; reverse
# Build a longer ramp from a brewer anchor set:
colorRampPalette(RColorBrewer::brewer.pal(7, "YlOrRd"))(100)   # == ylorrd()
```
`Paired` is the go-to for "two related series" (e.g. AFR vs ROW); `direction =
-1` flips which gets the dark shade. For sequential fills, `YlOrRd` is the house
default (see `ylorrd()`).

## 3. The corrected rainbow (many sectors)

`rainbow(n)` gives maximally distinct hues but its **pure green `#00FF2E` is too
light to read on white**. The fix swaps it for a deeper green `#00CC66`. Two
forms, depending on whether you want fixed hues or an arbitrary-length ramp:

```r
# (a) Distinct hues for a fixed, smallish set (<= ~12). The original idiom:
rainbow_sec(11)                       # = sub("#00FF2E","#00CC66", rainbow(11))
rainbow_sec(11, extra = "#000000")    # append an "other/services" class in black

# (b) Arbitrary n: turn those corrected hues into a colorRampPalette so you can
#     request ANY number of colours by interpolation. This is the generalization
#     of the rainbow fix:
rainbow_ramp(n)                       # smooth, on-brand, for any n
```
Definition of (b), for reference:
```r
rainbow_ramp <- function(n, extra = NULL)
  c(colorRampPalette(sub("#00FF2E", "#00CC66", rainbow(11)))(n), extra)
```
Use `rainbow_sec()` when you have a fixed sector list and want the punchiest
separation; use `rainbow_ramp()` when n is large or varies, or when a smooth
ordered progression reads better.

Apply to discrete scales:
```r
scale_fill_manual(values = rainbow_sec(11, extra = "#000000"))   # 12 classes
scale_colour_manual(values = rainbow_ramp(18))                   # 18 classes
```

## 4. viridis (continuous, perceptually uniform)

Families: `viridis`, `magma`, `inferno`, `plasma`, `cividis`, `turbo`. From
`viridisLite` (no need to attach `viridis`):

```r
library(viridisLite)
# continuous ggplot fill/colour
scale_fill_viridis_c(option = "inferno")          # built-in ggplot wrapper
scale_colour_gradientn(colours = inferno(256))    # explicit ramp
# discrete
scale_fill_viridis_d(option = "magma")
scale_fill_manual(values = magma(n))
```

### Clipping turbo (and other families)
`turbo`'s extreme ends are nearly black/dark-maroon and read poorly in a figure.
Clip them with `begin`/`end` to keep the legible middle band:

```r
turbo_clip(256)                       # = viridisLite::turbo(256, begin=.1, end=.9)
turbo_clip(256, begin = 0.05, end = 0.95)
scale_colour_gradientn(colours = turbo_clip(256))
```
The same `begin`/`end` trick works for any viridis family (e.g.
`inferno(256, begin = 0.1, end = 0.95)` to avoid pure black). Add `direction =
-1` to reverse.

### In tmap (v4)
tmap names palettes via cols4all: `values = "inferno"` / `"-inferno"` (reversed)
/ `"turbo"` / `"brewer.yl_or_rd"`. A manual colour vector also works:
`tm_scale_continuous(values = turbo_clip(256))`. See `maps-tmap.md`.

---

## Quick reference: which helper returns what

| Helper                | Returns | For |
|-----------------------|---------|-----|
| `vc_terms(5)` / `(6)` | 5/6 ordered names | value-chain decomposition stacks |
| `rainbow_sec(n, extra)` | n corrected-rainbow hues (+extra) | fixed sector set |
| `rainbow_ramp(n, extra)` | n interpolated corrected-rainbow colours | arbitrary n |
| `ylorrd(n=100)`       | n-step YlOrRd ramp | pheatmap / sequential fill |
| `turbo_clip(n, begin, end)` | n turbo colours, dark ends clipped | high-contrast continuous |

## Pitfalls
- Letting ggplot pick default colours for ordered data → the order is lost
  visually. Always pass an ordered `scale_*_manual(values = …)`.
- Using raw `rainbow()` → the pale green cell/segment vanishes on white; use
  `rainbow_sec()`/`rainbow_ramp()`.
- Raw `turbo()` in a paper → the near-black ends look like missing data; clip.
- Mapping the same concept to different colours across a figure set.
