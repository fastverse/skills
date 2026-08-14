# ggplot cookbook (house style)

Concrete, copy-adaptable recipes, **one section per chart type**. All assume
`source(".../pretty_plot.R")` and `library(ggplot2)`. They use collapse verbs for
data prep, but the ggplot layer is the transferable part (see `data-and-tables.md`).

**Saving** (every recipe): assign the plot to `p`, then
```r
pdf("figures/.../name.pdf", width = W, height = H); print(p); dev.off()
```
Do **not** use `ggsave()` or `dev.copy()`. `print()` is required or the PDF is blank.

## Table of contents
1. Bar chart (the workhorse)
2. Stacked / filled bars
3. Area chart
4. Time-series / line chart
5. Scatter plot
6. Faceting
7. Log / pseudo-log / sqrt axes
8. Value labels on bars
9. Overlaid bars with error bars
10. Text-repel scatter (many labels)
11. Legend placement
12. Line-wrapping long labels
13. Recurring scale snippets & pitfalls

---

## 1. Bar chart (the workhorse)
Ordered single-series magnitude across countries/sectors. Order → lock factor →
rotate labels.

```r
p <- DF |>
  roworder(-U) |>
  mutate(country = qF(country, sort = FALSE)) |>
  ggplot(aes(x = country, y = U, fill = Africa)) +
    geom_bar(stat = "identity") +
    scale_fill_brewer(palette = "Paired") +
    scale_y_continuous(n.breaks = 7, expand = expansion(mult = c(0, 0.03))) +
    labs(x = "Country", y = "Upstreamness") +
    guides(fill = "none") +                 # single highlight, no legend
    pretty_plot("right") + rotate_x()
pdf("figures/.../name.pdf", width = 10, height = 4); print(p); dev.off()
```

## 2. Stacked / filled bars
One geom, two positions:
- `position = "stack"` — absolute magnitudes summed (use `label_currency`).
- `position = "fill"` — composition 0–100% (use `scales::percent`, `expand = c(0,0)`).

```r
p <- LONG |>                                # long: one row per (x, variable)
  ggplot(aes(x = sector_code, y = value, fill = variable)) +
    geom_bar(stat = "identity", position = "fill") +
    scale_y_continuous(n.breaks = 7, expand = c(0, 0), labels = scales::percent) +
    scale_fill_manual(values = vc_terms(6)) +
    labs(x = "Sector", y = "Composition of Gross Exports", fill = "Term") +
    pretty_plot("right") + rotate_x()
pdf(...); print(p); dev.off()
```
Get LONG via `pivot()` (collapse) or `tidyr::pivot_longer()`. The `fill` variable
must be a factor in the desired stacking order (`factor(levels = …)`).

## 3. Area chart
Stacked areas over a continuous x (the time-series analogue of stacked bars):

```r
p <- LONG |>
  ggplot(aes(x = year, y = value, fill = variable)) +
    geom_area(position = "stack") +         # or position = "fill" for shares
    scale_x_continuous(n.breaks = 7, expand = c(0, 0)) +
    scale_y_continuous(n.breaks = 7, expand = c(0, 0),
                       labels = \(x) scales::dollar(x, scale = 1e-3, suffix = " B")) +
    scale_fill_manual(values = rainbow_sec(11)) +
    labs(x = "Year", y = "Value", fill = "Sector") +
    pretty_plot("right")
pdf(...); print(p); dev.off()
```
`expand = c(0, 0)` on both axes makes the band fill the panel edge-to-edge.

## 4. Time-series / line chart
Shares or levels over time, one line per series.

```r
p <- DF |>
  ggplot(aes(x = year, y = share, colour = measure)) +
    geom_line() +
    scale_y_continuous(n.breaks = 7, labels = scales::percent) +
    scale_x_continuous(n.breaks = 7, expand = c(0.02, 0)) +   # trim end margins
    scale_colour_brewer(palette = "Set1") +
    labs(x = "Year", y = "Africa's Share in World Trade", colour = "Flow") +
    pretty_plot("right")
pdf("figures/.../name.pdf", width = 8, height = 4); print(p); dev.off()
```
Add a smoothed guide with `geom_smooth(se = FALSE, linewidth = 0.5, span = 0.7,
linetype = "dashed")`. `expand = c(0.02, 0)` trims the empty margin at the ends
of a time axis.

## 5. Scatter plot
Relationship between two continuous variables; colour/shape a third.

```r
p <- DF |>
  ggplot(aes(x = upstreamness, y = downstreamness, colour = region)) +
    geom_point(size = 1.5, alpha = 0.8) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.5, linetype = "dashed") +
    scale_colour_brewer(palette = "Set1") +
    scale_x_continuous(n.breaks = 7) +
    scale_y_continuous(n.breaks = 7) +
    labs(x = "Upstreamness", y = "Downstreamness", colour = "Region") +
    pretty_plot("right")
pdf("figures/.../name.pdf", width = 5.5, height = 4.5); print(p); dev.off()
```
Label points without overlap → see §10 (ggrepel). Many short categories →
`pretty_plot("top")`.

## 6. Faceting
`facet_wrap(~ var, scales = "free_y")` — independent scales let each panel use
its full range. `pretty_plot()` already removes strip backgrounds.

```r
p <- DF |>
  ggplot(aes(x = year, y = value, colour = variable)) +
    geom_line() +
    facet_wrap(~ measure, scales = "free_y") +
    scale_colour_brewer(palette = "Paired", direction = -1) +
    scale_y_continuous(n.breaks = 7,
      labels = \(x) scales::dollar(x, scale = 1e-3, suffix = " B")) +
    labs(x = "Year", y = "Value", colour = "Flow:  ") +
    pretty_plot()
pdf("figures/.../name.pdf", width = 10, height = 3.5); print(p); dev.off()
```
Hide strip text when the facet identity is obvious: `theme(strip.text =
element_blank())`.

## 7. Log / pseudo-log / sqrt axes
For quantities spanning orders of magnitude. Always add `guide =
"axis_logticks"` for the minor-tick ladder.

```r
# strictly positive -> log10 with explicit human breaks
+ scale_y_log10(guide = "axis_logticks",
                breaks = c(0.01, 0.1, 1, 10, 30) / 100, labels = scales::percent)
+ theme(panel.grid.minor.y = element_blank())     # logticks replace minor grid

# values include 0 -> pseudo-log
+ scale_x_continuous(transform = scales::pseudo_log_trans(base = 10),
                     guide = "axis_logticks",
                     breaks = c(0.1, 0.5, 1, 2, 5, 10, 20, 50), expand = c(0, 0))

# compress a long right tail gently -> sqrt
+ scale_y_sqrt(breaks = c(0, 1, 2, 5, 10, 20, 50, 70) / 100,
               labels = scales::percent, expand = c(0, 0))
```

## 8. Value labels on bars
Add `geom_text` and give the axis headroom. Use `signif(value, 2)` for compact
numbers; nudge by an absolute amount.

```r
p <- {ggplot(DF, aes(x = sector, y = value, fill = sector, label = signif(value, 2))) +
   geom_bar(stat = "identity") +
   geom_text(nudge_y = 0.7) +
   facet_wrap(~ variable, scales = "free_y") +
   scale_y_continuous(n.breaks = 7, expand = expansion(c(0, 0.05))) +
   scale_fill_manual(values = rainbow_sec(11)) +
   labs(x = NULL, y = NULL, fill = "Sector") +
   pretty_plot("right") +
   theme(panel.grid.major.x = element_blank())}
pdf(...); print(p); dev.off()
```
Vertical labels above stacked bars: a separate totals frame +
`geom_text(aes(y = total, label = lab), angle = 90, hjust = 0, nudge_y = …,
inherit.aes = FALSE)` and `expand = expansion(mult = c(0, 0.15))`.

## 9. Overlaid bars with error bars (compare two populations)
Two semi-transparent bar layers at the same x, identity position, error bar on
one (e.g. Africa vs World).

```r
p <- {\(d)
  ggplot(d, aes(x = sector, y = Mean, fill = data)) +
    geom_bar(stat = "identity", alpha = 0.7, position = "identity",
             data = subset(d, data == "World")) +
    geom_bar(stat = "identity", alpha = 0.7, position = "identity",
             data = subset(d, data == "Africa")) +
    geom_errorbar(aes(ymin = `5%`, ymax = `95%`), data = subset(d, data == "Africa")) +
    scale_fill_manual(values = c("orange", "black")) +
    guides(fill = guide_legend(reverse = TRUE)) +
    labs(x = "Sector", y = "Upstreamness", fill = "Countries") +
    pretty_plot("right") + rotate_x()
}(DAT)
pdf(...); print(p); dev.off()
```

## 10. Text-repel scatter (many labels)
Label every point without overlap (`ggrepel`).

```r
p <- DF |>
  ggplot(aes(x = sector, y = value, label = iso3_o)) +
    geom_point(size = 0.8) +
    ggrepel::geom_text_repel(cex = 1.5, box.padding = 0.1, max.overlaps = 100) +
    scale_y_log10(guide = "axis_logticks", n.breaks = 11) +
    facet_wrap(~ variable, scales = "free_y") +
    labs(x = "Sector (Count)", y = NULL) +
    pretty_plot("right")
pdf(...); print(p); dev.off()
```

## 11. Legend placement
Match position to legend size (see also SKILL.md):
- **Few, short items** → `pretty_plot("top")` (default); one row with
  `guides(fill = guide_legend(nrow = 1))`.
- **Many / long items** → `pretty_plot("right")`; tall column with `ncol = 1`;
  pull a wide right legend inward with `theme(legend.margin = margin(l = -200))`.
- A trailing space in the legend title (`fill = "Flow:  "`) adds breathing room
  before the keys.

## 12. Line-wrapping long labels
```r
# wrap discrete axis tick labels at ~15 chars
+ scale_x_discrete(labels = scales::label_wrap(15))
# or pre-wrap in the data
mutate(sector = stringr::str_wrap(sector, width = 15))
# manual multi-line "name + (code/count)" labels (house idiom)
mutate(lab = paste0(sector, "\n(", code, ")"))
# wrap a long legend title
labs(fill = stringr::str_wrap("Composition of gross exports by term", 20))
```

## 13. Recurring scale snippets & pitfalls

```r
scale_y_continuous(n.breaks = 7, labels = scales::percent)                       # percent
scale_y_continuous(labels = \(x) scales::dollar(x, scale = 1e-6, suffix = " B")) # "$1.2 B"
scale_y_continuous(labels = scales::label_currency(suffix = "B", scale = 1e-3))
scale_y_discrete(limits = rev)                          # flip a horizontal bar order
guides(fill = guide_legend(nrow = 1))                   # or ncol = 1
```

**Pitfalls**
- Forgetting to lock factor order → ggplot alphabetizes; the ranked look is lost.
  Always `qF(x, sort = FALSE)` / `factor(levels = …)` after sorting.
- `size =` for line/border width on ggplot2 ≥ 4.0 → use `linewidth =`.
- Stacked/filled bars or areas floating above the axis → set lower `expand` to 0.
- Raw scientific notation on axes → always pass a `scales::` labeller.
- `ggsave()`/`dev.copy()` → use `pdf(); print(p); dev.off()` instead.
- Black outlines on bars (`geom_bar(colour = "black")`) → omit `colour`; the fill
  separates segments and an outline-per-bar reads as clutter.
- Over-converted units (axis showing `0.20 B`) → choose the scale so numbers read
  O(1–1000); keep `$M` for hundreds-of-millions, switch to `B` only past ~1000 M.
- Default outward ticks from `pretty_plot()` are intended — don't flip ticks
  inward; long outward ticks are part of the look.
- `pretty_plot()` must come before your own `theme(...)` tweaks (later `theme()`
  calls override earlier ones).
