# ---------------------------------------------------------------------------
# pretty_plot.R  --  House-style helpers for publication-quality R graphics
# ---------------------------------------------------------------------------
# Source this once at the top of a plotting script:
#     source("<skill>/scripts/pretty_plot.R")
# It only needs ggplot2 (lazily) for pretty_plot(), grDevices for the palettes,
# and tmap (v4) for tm_map_layout(). Nothing else is attached, so it is safe to
# source into any project regardless of how data is wrangled.
#
# SAVING: produce figures with the device idiom, NOT ggsave()/dev.copy():
#     pdf("figures/.../name.pdf", width = W, height = H)  # inches
#     print(p)        # print() is REQUIRED for ggplot/tmap objects in a script
#     dev.off()
# (base/pheatmap/migest/igraph draw directly between pdf() and dev.off().)
# ---------------------------------------------------------------------------

# --- The signature theme ----------------------------------------------------
# theme_bw() with a few deliberate tweaks that define the look:
#   * a real black panel border (not the grey theme_bw default)
#   * long axis ticks that point outward (0.4 lines) -> reads as "scientific"
#   * thin, unobtrusive gridlines (linewidth 0.25)
#   * strip backgrounds stripped to nothing, so facets feel light
#   * legend on top by default with tight margins (saves vertical space in a
#     paper). Pass "right" for many/long legend items (see legend notes below).
#
# Args:
#   lp   legend position: "top" (default), "right", "bottom", "left", "none"
#   sts  strip (facet label) text size
#   lbst legend box spacing in pt when lp == "top" (0 hugs the panel)
#   ...  passed to theme_bw() (e.g. base_size = 11)
pretty_plot <- function(lp = "top", sts = 12, lbst = 0, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("ggplot2 is required")
  ggplot2::theme_bw(...) + ggplot2::theme(
    strip.background = ggplot2::element_rect(colour = NA, fill = NA),
    strip.text       = ggplot2::element_text(size = sts),
    panel.border     = ggplot2::element_rect(colour = "black", linewidth = 0.5, fill = NA),
    axis.ticks       = ggplot2::element_line(colour = "black", linewidth = 0.25),
    panel.grid.major = ggplot2::element_line(linewidth = 0.25),
    axis.ticks.length = ggplot2::unit(0.4, "lines"),
    legend.position  = lp,
    legend.margin    = ggplot2::margin(t = 0, b = 2, unit = "pt"),
    legend.box.spacing = if (lp == "top") ggplot2::unit(lbst, "pt") else ggplot2::unit(8, "pt")
  )
}

# Rotate x-axis labels to vertical. Use whenever the x axis holds many country
# or sector CODES (ISO3, AFF/FBE/...). Add AFTER pretty_plot():
#   + pretty_plot("right") + rotate_x()
rotate_x <- function(angle = 270, hjust = 0, vjust = 0.5) {
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = angle, hjust = hjust, vjust = vjust))
}

# ===========================================================================
# Discrete colour palettes
# ===========================================================================
# Pick by WHAT the categories are (see references/colours-and-palettes.md):
#   2-4 contrasting flows .... RColorBrewer "Paired"/"Set1", or custom names
#   ordered decomposition .... vc_terms()  (hand-tuned orange -> blue)
#   ~10-12 sectors ........... rainbow_sec()  (corrected rainbow, distinct hues)
#   arbitrary n, smooth ...... rainbow_ramp() (corrected rainbow as a ramp)
#   sequential / continuous .. ylorrd(), or viridis (viridisLite::inferno etc.)

# rainbow() is the go-to for many sectors, BUT its pure green (#00FF2E) is too
# light to read on white; the house fix swaps it for a deeper green.
# rainbow_sec(): direct, distinct hues -- use for a fixed, smallish set (<=~12).
rainbow_sec <- function(n, extra = NULL) {
  c(sub("#00FF2E", "#00CC66", grDevices::rainbow(n)), extra)
}

# rainbow_ramp(): the SAME corrected rainbow turned into a colorRampPalette, so
# you can request an ARBITRARY number of colours by interpolating 11 anchors.
# Use when n is large or varies, or when you want a smooth ordered ramp.
#   scale_fill_manual(values = rainbow_ramp(15))
rainbow_ramp <- function(n, extra = NULL) {
  anchors <- sub("#00FF2E", "#00CC66", grDevices::rainbow(11))
  c(grDevices::colorRampPalette(anchors)(n), extra)
}

# Ordered value-chain decomposition terms, domestic -> foreign. The 5-term set
# (NDAVAX, REF, DDC, FVA, FDC) and the 6-term set that prepends DAVAX (red).
#   scale_fill_manual(values = vc_terms(5))
vc_terms <- function(n = 5) {
  full <- c("red2", "orange", "yellow2", "green2", "dodgerblue4", "dodgerblue")
  if (n == 5) full[-1] else if (n == 6) full else stop("vc_terms supports 5 or 6 terms")
}

# ===========================================================================
# Sequential / continuous ramps
# ===========================================================================
# 100-step YlOrRd ramp for pheatmap / continuous fills.
ylorrd <- function(n = 100) {
  if (!requireNamespace("RColorBrewer", quietly = TRUE)) stop("RColorBrewer required")
  grDevices::colorRampPalette(RColorBrewer::brewer.pal(7, "YlOrRd"))(n)
}

# turbo with its very dark ends clipped off (the raw turbo endpoints are nearly
# black/maroon and read poorly). begin/end keep the legible middle band.
#   scale_colour_gradientn(colours = turbo_clip(256))
turbo_clip <- function(n = 256, begin = 0.1, end = 0.9, direction = 1) {
  if (!requireNamespace("viridisLite", quietly = TRUE)) stop("viridisLite required")
  viridisLite::turbo(n, begin = begin, end = end, direction = direction)
}

# ===========================================================================
# tmap v4 map layout
# ===========================================================================
# Reusable map chrome: no frame, legend INSIDE the map at bottom-left (maps have
# empty ocean/corner space -- never waste a margin on the legend), no legend
# frame, modest sizes, extra top inner margin so a SW-corner legend clears
# southern Africa. Add with `+`:
#   tm_shape(x) + tm_polygons(...) + tm_map_layout()
# NB: in tmap v4 the *content* of a legend (title, breaks, palette) belongs in
# tm_polygons(fill.scale=, fill.legend=); this helper only sets global chrome.
tm_map_layout <- function() {
  if (!requireNamespace("tmap", quietly = TRUE)) stop("tmap (>= 4) required")
  tmap::tm_layout(
    frame = FALSE,
    legend.position  = tmap::tm_pos_in("left", "bottom"),
    legend.text.size = 0.9,
    legend.title.size = 1.2,
    legend.frame = FALSE,
    inner.margins = c(0.02, 0.02, 0.26, 0.02)
  )
}
