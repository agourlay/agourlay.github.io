#!/usr/bin/env bash
#
# Scaffold a new blog post with the correct front matter.
#
# Serene serves posts under /posts/<slug>/ by default, but this blog publishes them
# at the root /<slug>/ (to preserve permalinks). That requires a `path` field in each
# post's front matter — this script sets it automatically so you never have to remember.
#
# Usage: ./new-post.sh "My Great Post Title"
#
set -euo pipefail

title="${*:-}"
if [ -z "$title" ]; then
  echo "usage: ./new-post.sh \"<post title>\"" >&2
  exit 1
fi

date="$(date +%F)"
# slug: lowercase, non-alphanumerics -> dashes, trim leading/trailing dashes
slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
file="content/posts/${date}-${slug}.md"

if [ -e "$file" ]; then
  echo "refusing to overwrite existing file: $file" >&2
  exit 1
fi

cat > "$file" <<EOF
+++
title = "${title}"
date = ${date}
path = "${slug}"

[taxonomies]
tags = []
+++

EOF

echo "created ${file}"
echo "  URL will be: /${slug}/"
