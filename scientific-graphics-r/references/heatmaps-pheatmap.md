# Heatmaps with pheatmap

The house heatmap shows a matrix (e.g. sectors × regions) where the **colour
encodes magnitude on a log scale** but the **printed number is the raw value**.
This resolves the classic tension: trade/value matrices span orders of
magnitude, so a linear colour scale washes out everything but the largest cell,
yet readers still want the actual figures.

## The recipe

```r
library(pheatmap); library(RColorBrewer)

# 1. Get a numeric matrix with row/col names (qM from collapse, or as.matrix).
m <- DATA |>
  pivot(ids = "sector_code", values = "NDAVAX", names = "REC", how = "w") |>
  qM(1)                                  # first column -> rownames

# 2. Colour by log10(m); annotate with the rounded raw values. pheatmap draws
#    to the open device, so wrap it in the house pdf()/dev.off() idiom.
pdf("figures/.../name.pdf", width = 4.5, height = 4.5)
pheatmap(log10(m),
         cluster_rows = FALSE, cluster_cols = FALSE,  # keep your chosen order
         display_numbers = round(m, 2),               # RAW values in cells
         legend = FALSE,                              # numbers make it redundant
         number_color = "black",
         border_color = NA,
         color = colorRampPalette(brewer.pal(7, "YlOrRd"))(100))  # == ylorrd()
dev.off()
```

Why each choice:
- **`log10(m)` for colour, `round(m, 2)` for numbers** — the signature move.
- **`cluster_rows/cols = FALSE`** — you almost always want a meaningful manual
  order (sectors grouped, regions by size), not dendrogram order. Set the order
  upstream with `colorder()` / by ordering the matrix rows.
- **`legend = FALSE`** — the in-cell numbers carry the quantity; a colour bar is
  clutter. (Turn it back on only if you drop `display_numbers`.)
- **`border_color = NA`, `number_color = "black"`** — clean, borderless cells
  with legible labels.
- **`color = colorRampPalette(brewer.pal(7, "YlOrRd"))(100)`** — 100-step
  sequential ramp. The bundled `ylorrd()` helper returns exactly this.

## Saving

Use the house idiom: open `pdf(file, width, height)`, call `pheatmap(...)`
(no `filename=`), then `dev.off()`. pheatmap draws to the active device on
construction, so no `print()` is needed.

pheatmap also has a built-in `filename=` argument that opens its own device and
writes the file directly — if you use it, do **not** wrap the call in
`pdf()/dev.off()` (you'd get an empty outer PDF). Prefer the explicit
`pdf()/dev.off()` wrap for consistency with every other figure in this style.

## Gotchas
- `log10(0)` is `-Inf` and `log10(neg)` is `NaN` → those cells break the colour
  scale. Guard with a floor (e.g. `log10(pmax(m, 1e-6))`) or ensure the matrix
  is strictly positive before logging. The displayed `round(m, 2)` still shows
  the true value.
- Matrix must be numeric with dimnames; a data.frame won't do — convert with
  `qM(1)` (collapse, first col → rownames) or `as.matrix()` after setting
  rownames.
- `display_numbers` must have the **same dimensions** as the colour matrix; pass
  `round(m, 2)`, not a reshaped/reordered copy.
- Reordering columns for presentation: do it on the matrix (`colorder(...)`
  before `qM`, or `m[, new_order]`) so colour and numbers stay aligned.
