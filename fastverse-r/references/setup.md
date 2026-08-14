# Loading, configuring and managing the fastverse

For anything about collapse itself — including `set_collapse()` and namespace
masking, which this file only touches on in the context of `.fastverse` config
files — use the **`collapse-r`** skill.

The `fastverse` package is a loader and manager, not a computational package.
It attaches a set of packages, reports their versions and namespace conflicts,
and lets you extend or replace that set for a session, a project, or
permanently.

## Table of contents
- [Attaching](#attaching)
- [Why the order matters](#why-the-order-matters)
- [Extending for a session](#extending-for-a-session)
- [Project configuration: the `.fastverse` file](#project-configuration-the-fastverse-file)
- [Permanent global extension](#permanent-global-extension)
- [Dependencies, updates and sitreps](#dependencies-updates-and-sitreps)
- [Creating a separate verse](#creating-a-separate-verse)
- [Options](#options)
- [OpenMP](#openmp)

## Attaching

```r
library(fastverse)
# -- Attaching packages ------------------------------- fastverse 0.3.4 --
# v data.table 1.18.4     v kit        0.0.21
# v magrittr   2.0.5      v collapse   2.1.7
# -- Conflicts ---------------------------------- fastverse_conflicts() --
# x data.table::%notin%() masks base::%notin%()
```

The version banner is not decoration — it is a replicability record. When a
script is rerun a year later, the banner in the saved log says which versions
produced the output.

```r
fastverse_packages()          # what is in the current verse
fastverse_conflicts()         # recheck conflicts at any point
is_attached("sf")             # TRUE/FALSE
is_installed("qs2")
```

## Why the order matters

Packages are attached in the order listed, and later ones mask earlier ones.
The default order is **data.table, magrittr, kit, collapse** — collapse last, on
purpose. Three functions exist in more than one package:

| Function | In | Winner |
|---|---|---|
| `funique` | collapse, kit | collapse |
| `fduplicated` | collapse, kit | collapse |
| `fdroplevels` | collapse, data.table | collapse |

These three clashes are **excluded from the conflict report** deliberately —
they are the intended resolution, not an accident. (`collapse::D` is also
excluded, since the clash with `stats::D` is expected.) Everything else is
reported.

If you write your own package list, keep collapse after kit and data.table
unless you specifically want kit's matrix-capable `funique` or data.table's
level-preserving `fdroplevels` to win.

## Extending for a session

```r
fastverse_extend(..., install = FALSE, permanent = FALSE,
                 check.conflicts = !isTRUE(getOption("fastverse.quiet")),
                 topics = NULL, repos = getOption("repos"))
```

```r
fastverse_extend(sf, s2, fixest)
fastverse_extend(qs2, sf, units, sfnetworks, tmap, install = TRUE)   # install if missing
fastverse_extend(pkgs_vector)                                        # a character vector works too
```

Loading everything through `fastverse_extend()` rather than a pile of
`library()` calls is worth the habit: you see each package's version and its
conflicts as it arrives, and `fastverse_conflicts()` stays meaningful later.

Extensions are recorded in `options("fastverse.extend")`, so you can also set
that before `library(fastverse)`:

```r
options(fastverse.extend = c("qs", "fst"))
library(fastverse)
```

Detaching:

```r
fastverse_detach()                                  # detach, keep loaded, keep options
fastverse_detach(data.table, kit)                   # selected packages
fastverse_detach(session = TRUE, unload = TRUE)     # full teardown, clear options
```

`fastverse_detach()` also works on packages that are not part of the verse.

## Project configuration: the `.fastverse` file

This is the recommended way to pin a project's stack. Put a file named
`.fastverse` (no extension) in the project root; `library(fastverse)` reads it
and ignores any global configuration.

```
_opt_fastverse.install = TRUE
_env_ARMA_64BIT_WORD = TRUE

magrittr, sf, data.table, kit, collapse, ggplot2, fixest, qs

_opt_max.print = 100
_opt_kit.nThread = 4L
```

Rules:

- **All** packages to load must be listed, including the core four. Omitting one
  is how you exclude it.
- Packages attach in file order, left to right, top to bottom. They may span
  several lines but must be contiguous — options cannot be interleaved.
- Lines starting `_opt_` set options; `_env_` sets environment variables.
  Anything before the package block is applied *before* attaching, anything
  after is applied *after*. That ordering is the reason to prefer `.fastverse`
  over `.Rprofile`: some options must be set before a package loads
  (`collapse_mask`, `fastverse.install`) and others must be set after, because
  loading would overwrite them.

A real example from a project that wants collapse's unprefixed verbs:

```
_opt_collapse_mask = c("manip", "helper")
_opt_fastverse.install = TRUE

data.table, magrittr, kit, collapse, qs,
parallel, matrixStats, ggplot2, readxl

_opt_max.print = 100
```

`collapse_mask` changes which functions exist under which name — see the
`collapse-r` skill before setting it, and do not add it to someone's project on
your own initiative.

## Permanent global extension

`fastverse_extend(..., permanent = TRUE)` and
`fastverse_detach(..., permanent = TRUE)` write to a config file inside the
installed package directory, so the change survives across sessions:

```r
fastverse_extend(xts, zoo, roll, anytime, permanent = TRUE)
fastverse_detach(kit, magrittr, permanent = TRUE)
fastverse_reset()      # undo all permanent changes and clear options
```

The catch: the config lives in the package directory, so **reinstalling
fastverse erases it**. For anything you care about reproducing, use a
`.fastverse` project file instead — it is version-controlled with the code.

## Dependencies, updates and sitreps

```r
fastverse_deps(pkg = fastverse_packages(), recursive = FALSE, repos = getOption("repos"))
fastverse_sitrep(...)
fastverse_update(..., install = FALSE, repos = getOption("repos"))
fastverse_install(..., only.missing = TRUE, install = TRUE, repos = getOption("repos"))
```

```r
fastverse_deps(recursive = TRUE)   # data frame: package, repos version, local version, behind
fastverse_sitrep()                 # same, formatted, plus R version and which config files are active
fastverse_update()                 # prints the install.packages() call to run
fastverse_update(install = TRUE)   # just does it
```

`fastverse_sitrep()` is what to paste into a bug report — it shows the R
version, whether a global or project config file is in play, and every package
version with its update status.

Development versions live on an r-universe server, exposed as a global macro:

```r
.fastverse_repos
# fastverse "https://fastverse.r-universe.dev"   CRAN "https://cloud.r-project.org"

fastverse_update(repos = .fastverse_repos)
fastverse_install(collapse, kit, only.missing = FALSE, repos = .fastverse_repos)
```

## Creating a separate verse

```r
fastverse_child(name, title, pkg, maintainer, version = "0.1.0", dir = ".",
                theme = c("fastverse", "tidyverse"), install = TRUE, keep.dir = TRUE)
```

```r
fastverse_child(
  name = "tsverse",
  title = "Time Series Package Verse",
  pkg = c("xts", "roll", "zoo", "tsbox", "urca", "tseries", "forecast"),
  maintainer = 'person("Given", "Family", role = "cre", email = "you@example.com")',
  dir = "~/Documents"
)
```

The child inherits most of the machinery — it can be extended for a session and
configured per project (via a `.tsverse` file and `tsverse.*` options) — but
cannot be globally extended permanently and cannot itself have children. It
builds from a prepared branch of the fastverse GitHub repo, so no devtools
needed.

## Options

| Option | Effect |
|---|---|
| `fastverse.quiet = TRUE` | suppress all startup and extension messages, including conflicts |
| `fastverse.styling = FALSE` | disable coloured console output |
| `fastverse.extend = c(...)` | packages to add; set before `library(fastverse)`, also populated by `fastverse_extend()` |
| `fastverse.install = TRUE` | install any missing packages before attaching |

`fastverse_extend(..., check.conflicts = FALSE)` suppresses the conflict check
for one call without going fully quiet.

## OpenMP

Three of the four packages multithread, each with its own control and its own
default:

```r
setDTthreads(4);   getDTthreads()              # data.table — defaults to ~half the cores
set_collapse(nthreads = 4)                     # collapse   — defaults to 1
options(kit.nThread = 4L)                      # kit        — defaults to 1
```

Two things to check before spending time on threading:

**Nesting oversubscribes.** data.table already parallelizes over groups in
`by=`. A multithreaded collapse or kit call inside that `j` fights it for cores
and is usually slower than the single-threaded version. Keep the inner call at
one thread.

**macOS CRAN binaries of collapse and kit have no OpenMP.** kit announces it on
attach:

```
Attaching kit 0.0.21 (OPENMP disabled using 1 thread)
```

collapse says nothing, so test it:

```r
x <- rnorm(1e7)
system.time(fsum(x, nthreads = 1))
system.time(fsum(x, nthreads = 4))    # same => no OpenMP
```

data.table ships its own OpenMP runtime and is unaffected. To enable it for the
others, install OpenMP for macOS (<https://mac.r-project.org/openmp/>) and then
reinstall from source or from r-universe:

```r
fastverse_install(data.table, collapse, kit, only.missing = FALSE, repos = .fastverse_repos)
```

Even with OpenMP, expect gains mainly on large *ungrouped* vector operations —
grouping itself is serial, so a grouped statistic on one column often shows no
speed-up at all.
