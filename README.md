# fastverse skills

Claude Code skills for the [collapse](https://fastverse.org/collapse/) and [fastverse](https://fastverse.org/fastverse/) R packages.

- **collapse-r** — expert guidance for `collapse`. Stands alone.
- **fastverse-r** — expert guidance for the fastverse (`data.table`, `collapse`, `kit`, `magrittr`). Requires the `collapse-r` skill.
- **scientific-graphics-r** — experimental. Publication-quality figures with `ggplot2`, `tmap`, `pheatmap`, `migest`, and `igraph` in a consistent scientific theme, using `collapse` for data preparation.

## Installation

Clone the repo, then copy (or symlink) the skill folder(s) you want into your Claude Code skills directory — `~/.claude/skills/` for all projects, or `<project>/.claude/skills/` for one project only.

```sh
git clone https://github.com/fastverse/skills fastverse-skills

mkdir -p ~/.claude/skills
ln -s "$(pwd)/fastverse-skills/collapse-r" ~/.claude/skills/collapse-r
ln -s "$(pwd)/fastverse-skills/fastverse-r" ~/.claude/skills/fastverse-r
ln -s "$(pwd)/fastverse-skills/scientific-graphics-r" ~/.claude/skills/scientific-graphics-r
```

`fastverse-r` reuses guidance from `collapse-r`, so install both together.

Alternatively, just give a Claude Code agent this repo's URL and ask it to install the skills globally.
