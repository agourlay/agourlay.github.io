# Blog

Source of my blog, built with [Zola](https://www.getzola.org/).

> **Zola version:** pinned to **0.22.x**. The theme is not yet compatible with Zola 0.23
> (Tera v2 / shortcode removal), so do not upgrade past 0.22 until the theme migrates.

## Theme

Using the [serene](https://github.com/isunjn/serene) theme, added as a submodule and
pinned to a release tag:

```bash
git submodule add https://github.com/isunjn/serene themes/serene
git -C themes/serene checkout v5.7.0
```

Theme docs: `themes/serene/USAGE.md`.

## Content layout

```
content/
├── _index.md            # home landing page (home.html)
├── about/_index.md      # about page (prose.html)  — also redirects /pages/about/
└── posts/
    ├── _index.md        # blog section (blog.html + post.html)
    └── <date>-<slug>.md # one file per post
```

### Permalinks (important)

Serene serves posts under `/posts/<slug>/` by default, but this blog keeps every post
at the **root** `/<slug>/` to preserve the original URLs and RSS entry IDs (so existing
links and feed subscribers are never disrupted).

This is done with a `path` field in each post's front matter:

```toml
+++
title = "..."
date = 2022-07-11
path = "rust-performance-retrospective-part1"   # -> https://.../rust-performance-retrospective-part1/
[taxonomies]
tags = ["Rust", "performance"]
+++
```

**When adding a new post, set `path` to the desired slug** (matching how the URL should
read), otherwise it will publish under `/posts/...` instead of the root.

The easiest way is the scaffolding script, which fills in `date` and `path` for you:

```bash
./new-post.sh "My Great Post Title"
# -> creates content/posts/<today>-my-great-post-title.md, published at /my-great-post-title/
```

### Taxonomies

Only **tags** have term pages in Serene. The retrospective "series" is therefore a
`series` **tag** (categories have no term pages in this theme). Old `/categories/...`
and `/page/1/` URLs are preserved via redirect stubs in `static/`.

## Customizations

Kept in the site (never edit files inside `themes/serene/`, so theme updates stay clean):

- `templates/_footer.html` — overrides the footer to add the GitHub sponsor line and a
  plain RSS link.
- `templates/_head_extend.html` — small CSS: avatar `object-fit` (so a non-square photo
  isn't distorted), stacks the footer copyright/sponsor lines, and floats the RSS +
  light/dark toggle into a fixed top-right cluster (visible on landing).
- `static/img/` — favicons (`favicon-16x16.png`, `favicon-32x32.png`, `apple-touch-icon.png`).
- `static/categories/`, `static/page/` — redirect stubs preserving old anpu URLs.

### Callouts & figures

Callouts and image captions use Serene shortcodes: `note` / `tip` / `important` /
`warning` / `caution`, `quote`, and `figure`. These are Serene-specific and will need
converting (e.g. to `> [!NOTE]` GitHub-alert syntax) if the theme ever moves to Zola 0.23.

## Development & deployment

- Local preview: `zola serve` (requires Zola 0.22.x).
- GitHub Pages via [shalzz/zola-deploy-action](https://github.com/shalzz/zola-deploy-action)
  pinned to `@v0.22.1` in `.github/workflows/deploy.yml` (must match the Zola version above).
