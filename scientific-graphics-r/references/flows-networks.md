# Flow diagrams (migest) and networks (igraph)

Two ways to show who-sends-what-to-whom: a **chord diagram** (compact, circular,
great for a handful of regions/RECs) and a **directed network** (spatial-ish
layout, good for many countries with a few dominant links).

---

## Chord diagrams with migest

`migest::mig_chord()` draws an origin→destination chord diagram from a **long**
flow frame: three columns `orig, dest, flow` (extra columns are ignored). It
wraps `circlize` with sensible migration-style defaults (directional arrows,
gaps, auto labels).

### Recipe

```r
library(migest)

# Long flows: from, to, value. Make values human-scaled (e.g. USD billions)
# BEFORE plotting so the on-chart numbers read nicely.
flows <- AFR_RI_AGG |> compute(EX = EX / 1e3, keep = .c(rec_o, rec_d))

pdf("figures/.../name.pdf", width = 8, height = 8)
mig_chord(flows)          # columns interpreted as orig, dest, flow in order
dev.off()
```

A square map matrix can be melted to long first:

```r
GVC_REC_table |>
  select(-RVC) |>         # keep the REC × REC value columns
  pivot("REC") |>         # -> long: REC, variable, value  (collapse pivot)
  subset(REC != variable) |>   # drop the diagonal (within-region) if desired
  mig_chord()
```

### Common framings (each its own PDF)
- **All flows incl. ROW**: keep every destination.
- **Intra-African only**: `subset(rec_d != "ROW")`.
- **Between-region only**: `subset(rec_d != "ROW" & rec_o != rec_d)` (drops the
  diagonal, so the chart shows only cross-REC linkages).
- **Normalized**: divide flows by origin size (e.g. `/ GDP`) before plotting to
  compare integration intensity rather than raw volume.

### Notes & gotchas
- **Column order matters**: `mig_chord()` reads the first three columns as
  `orig, dest, flow`. Use `compute(..., keep=)` / `colorder()` so they line up,
  or pass an explicit named frame.
- Always wrap in `pdf(...); mig_chord(...); dev.off()` — it draws to the active
  device (no `print()` needed). Avoid `dev.copy(pdf, …)`: it copies whatever is
  on screen and is fragile in scripts.
- Scale values to readable units (billions) up front; the chart prints axis
  ticks from the raw numbers.
- Very many sectors/regions → too many tiny chords; aggregate to RECs/broad
  sectors first, or switch to a network.

---

## Directed networks with igraph

For country-level flows where a chord diagram would be unreadable: build a
directed graph, lay it out with weighted Fruchterman–Reingold, size nodes by
total outflow and edges by flow.

### Recipe

```r
library(igraph)

# Edge list: from, to, value. Trim to the strongest links so the plot is legible.
trade_data <- DATA[, .(value = sum(GVC)), by = .(from = country, to = part_country)]
outflows   <- aggregate(trade_data$value, by = list(trade_data$from), FUN = sum)
trade_data <- trade_data |> roworder(-value) |> ss(1:50)   # top 50 edges

g <- graph_from_data_frame(trade_data, directed = TRUE)
E(g)$weight  <- trade_data$value
vsize        <- setNames(outflows$x, outflows$Group.1)
V(g)$size    <- vsize[V(g)$name]
layout       <- layout_with_fr(g, weights = E(g)$weight, niter = 10000)

pdf("figures/.../name.pdf", width = 8, height = 8)
plot(g,
     layout            = layout,
     edge.arrow.mode   = "-",                 # undirected-looking; no arrowheads
     edge.width        = E(g)$weight^0.9 / 15, # sublinear so big links don't dominate
     edge.color        = "gray85",
     vertex.shape      = "circle",
     vertex.color      = "lightblue",
     vertex.frame.color = NA,                  # no node outline
     vertex.size       = V(g)$size^0.4 + 5,    # sublinear node scaling
     vertex.label      = V(g)$name,
     vertex.label.family = "sans",
     vertex.label.color  = "gray20",
     vertex.label.cex    = 0.7)
dev.off()
```

### Design choices that make it readable
- **Trim edges** (`roworder(-value) |> ss(1:50)`) — full bilateral graphs are
  hairballs. Keep the top-N links (or threshold by value).
- **Sublinear scaling** for both edges (`weight^0.9 / 15`) and nodes
  (`size^0.4 + 5`) so the largest don't swamp the canvas — tune the divisor /
  exponent to taste.
- **Muted colours, no frames** (`gray85` edges, `lightblue` nodes,
  `vertex.frame.color = NA`) keep focus on structure.
- **FR layout weighted by flow** (`layout_with_fr(g, weights = E(g)$weight)`)
  pulls strongly-linked nodes together; raise `niter` for stability.
- Drop tiny/island states that distort the layout (e.g. `subset(from != "ESH" &
  to != "ESH")`).

### ggraph alternative (themed, ggplot-style)
If you want a network in the ggplot idiom (e.g. for visual consistency with the
other figures):

```r
library(ggraph)
p <- ggraph(g, layout = "stress") +
  geom_edge_link0(aes(edge_linewidth = weight), edge_colour = "grey66") +
  geom_node_point(aes(size = size), shape = 21, fill = "lightblue") +
  geom_node_text(aes(label = name), family = "sans") +
  scale_edge_width_continuous(range = c(0.2, 3)) +
  scale_size_continuous(range = c(1, 6)) +
  theme_graph() + theme(legend.position = "none")
pdf("figures/.../name.pdf", width = 8, height = 8); print(p); dev.off()
```
`theme_graph()` (not `pretty_plot()`) is appropriate here — a network has no
axes. Save with the device idiom (`pdf(); print(p); dev.off()`), not `ggsave()`.
