# Choropleth maps with tmap v4

Target **tmap ≥ 4**. The v4 API splits what v3 packed into `tm_polygons()` into
three arguments: the variable (`fill=`), how values map to colour
(`fill.scale = tm_scale_*()`), and the legend (`fill.legend = tm_legend()`).
All recipes below are verified against tmap 4.3.

## Setup

```r
library(sf); library(tmap)
africa_map <- st_read(".../Africa_Countries") |> st_make_valid()
# Crop to a tidy Africa frame (lon/lat, WGS84)
bbox <- st_bbox(c(xmin = -20, ymin = -34, xmax = 52, ymax = 36), crs = st_crs(4326))
```

Join your data onto the sf object by ISO3 *before* mapping (collapse `join`,
`dplyr::left_join`, or `merge`), keeping the geometry:

```r
map_df <- join(africa_map, mutate(DATA, Y = (I2E + E2R) * 100),
               on = c("ISO_3DIGIT" = "country"))
```

## Sequential numeric choropleth (the workhorse)

Jenks (natural-breaks) classes with a reversed inferno ramp, legend inside the
map at bottom-left via the bundled `tm_map_layout()`.

```r
pdf("figures/.../name.pdf", width = 8, height = 8)
print(
  tm_shape(map_df, bbox = bbox) +
    tm_polygons(
      fill = "Y",
      fill.scale  = tm_scale_intervals(style = "jenks", n = 10, values = "-inferno"),
      fill.legend = tm_legend(title = "RVCs/GEXP (%)")) +
    tm_map_layout()
)
dev.off()
```

Key points:
- **`print()` is mandatory** when the map is built inside `pdf()/dev.off()`, a
  loop, or a function — a bare tmap object won't draw to the device otherwise.
- `tm_scale_intervals(style = "jenks", n = 10, …)` replaces v3's
  `style="jenks", n=10`. Other styles: `"quantile"`, `"equal"`, `"pretty"`,
  `"fisher"`, `"cont"`-like behaviour via `tm_scale_continuous()`.
- For a smooth (unclassed) ramp use `tm_scale_continuous(values = "-inferno")`.

## Categorical choropleth (e.g. "main sector per country")

```r
tm_shape(africa_map, bbox = bbox) +
  tm_polygons(
    fill = "main_sector",
    fill.scale  = tm_scale_categorical(values = rainbow_sec(11, extra = "#000000")),
    fill.legend = tm_legend(title = "Main RVC Sector")) +
  tm_map_layout()
```
`tm_scale_categorical(values = <vector or palette name>)` replaces v3's
`palette = c(...)` for discrete fills. A manual colour vector works directly.

## Looping over sectors / years

One PDF per category. Note `print()` inside the loop.

```r
for (sec in c("AFF", "FBE", "PCM", "MIN", "SRV")) {
  pdf(sprintf("figures/.../%s_RVC_Map.pdf", sec), width = 8, height = 8)
  print(
    tm_shape(join(africa_map, subset(DATA, sector_code == sec, country, RVC),
                  on = c("ISO_3DIGIT" = "country")), bbox = bbox) +
      tm_polygons(fill = "RVC",
                  fill.scale  = tm_scale_intervals(style = "jenks", n = 10, values = "-inferno"),
                  fill.legend = tm_legend(title = sprintf("%s RVC ($M)", sec))) +
      tm_map_layout())
  dev.off()
}
```

## Palette names in v4

See `colours-and-palettes.md` for choosing a palette; this section covers the
v4-specific naming. v4 routes colours through the **cols4all** system. Names
differ from v3:
- viridis family: `"viridis"`, `"inferno"`, `"magma"`, `"plasma"`, `"cividis"`
  (prefix `-` to reverse, e.g. `"-inferno"`).
- Brewer: `"brewer.yl_or_rd"`, `"brewer.set1"`, `"brewer.paired"`,
  `"brewer.set3"`, etc.
- A manual colour vector (hex or R names) is always accepted by any `tm_scale_*`.
- **Clip a palette natively with `values.range`.** `tm_scale_*(values = "turbo",
  values.range = c(0.1, 0.9))` drops turbo's near-black blue/red ends (they read
  as missing data and look alike). **Always clip `turbo` to `c(0.1, 0.9)`** — on
  `tm_scale_continuous`, `tm_scale_intervals`, and `tm_scale_categorical` alike.
  This is the tmap-native equivalent of `turbo_clip()` (see `colours-and-palettes.md`).
- Discover/preview interactively with `cols4all::c4a_gui()` or list with
  `cols4all::c4a_palettes()`.

## Legend control

Keep the **legend title short** — it sits inside the map, so a long title
(e.g. "Regional value chains as a share of gross exports (%)") crowds the
panel. Use a compact label like `"RVC share (%)"` or `"RVCs/GEXP (%)"`, and
wrap if needed with `\n` / `stringr::str_wrap()`.

The bundled `tm_map_layout()` sets global chrome (no frame, legend bottom-left,
no legend frame, sizes, extra top inner margin so a SW-corner legend clears
southern Africa). To override per-map, pass options into the layer's legend:

```r
fill.legend = tm_legend(
  title = "…",
  position = tm_pos_in("right", "bottom"),  # inside, or tm_pos_out(...) outside
  text.size = 0.9, title.size = 1.2,
  frame = FALSE, bg = FALSE,
  orientation = "portrait")                 # or "landscape"
tm_legend_hide()                            # suppress a legend entirely
```

## v3 → v4 migration cheat-sheet

Old project map code is usually v3. It still *runs* under v4 (with migration
messages) but should be ported:

| tmap v3 (legacy)                                  | tmap v4 |
|---------------------------------------------------|---------|
| `tm_polygons(col = "Y")`                          | `tm_polygons(fill = "Y")` (`col` now = border colour) |
| `tm_polygons(..., style = "jenks", n = 10)`       | `fill.scale = tm_scale_intervals(style = "jenks", n = 10)` |
| `tm_polygons(..., palette = "inferno")`           | `fill.scale = tm_scale_*(values = "-inferno")` |
| `tm_polygons(..., title = "X")`                   | `fill.legend = tm_legend(title = "X")` |
| `tm_layout(legend.text.size = 1.3)`               | `tm_legend(text.size = …)` (or still works in `tm_layout`) |
| `tm_layout(legend.position = c(0.05, 0.01))`      | `tm_legend(position = tm_pos_in("left","bottom"))` |
| `%>% tm_shape() + ...` then `dev.copy(pdf, ...)`  | `pdf(...); print(tm_shape() + ...); dev.off()` |

`dev.copy(pdf, …); dev.off()` (capturing whatever's on screen) works but is
fragile in scripts — prefer opening the `pdf()` device first and `print()`-ing
the object into it.

## Pitfalls
- **No `print()`** inside `pdf()`/loop/function → blank or last-only PDF. This is
  the #1 tmap-in-a-script bug.
- Passing a v3 `palette=`/`style=`/`title=` to `tm_polygons` in v4 → it works but
  spams messages; move them into `fill.scale`/`fill.legend`.
- Data not joined to geometry, or ISO3 keys mismatched (e.g. Natural Earth omits
  small island states like MUS, SYC) → those polygons render as NA/grey. Check
  the join keys; backfill missing geometries from `rnaturalearth` if needed.
- `tm_crs("auto")` silences the projection tip and gives a nicer equal-area look,
  but the lon/lat bbox above is fine for a quick Africa map.
- **Degenerate jenks class** (a legend entry like `2.04 – 2.03`) appears when the
  smallest values are near-tied, so jenks carves a one-value class. Cosmetic, but
  to avoid it: drop `n` (fewer classes), or use `style = "fisher"` /
  `"quantile"`, or `tm_scale_continuous()` for a smooth (unclassed) ramp.
