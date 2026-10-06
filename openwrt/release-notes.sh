#!/bin/bash
## Release notes (Markdown) from README.changes.md: the sections added since
## the previous release tag, then where to get the images.
##
## USAGE
##   ./openwrt/release-notes.sh [PREV] > notes.md
##
##   PREV   git ref of the previous release (default: the latest v* tag
##          before HEAD); without one, only the newest section
##
## ENV
##   REPO=owner/name   for the firmware selector link (default:
##                     $GITHUB_REPOSITORY, else 220242/khadas_edge-openwrt)

set -euo pipefail
cd "$(dirname "$0")/.."

CHANGES=README.changes.md
REPO=${REPO:-${GITHUB_REPOSITORY:-220242/khadas_edge-openwrt}}
PREV=${1-$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || true)}

old=$(mktemp)
trap 'rm -f "$old"' EXIT
[ -n "$PREV" ] && git show "$PREV:$CHANGES" > "$old" 2>/dev/null || true

# "## " sections of the current change log whose heading the previous one
# does not have (new sections go on top, older ones may be edited later)
notes=$(awk -v old="$old" '
	BEGIN {
		while ((getline l < old) > 0) if (l ~ /^## /) seen[l] = 1
		haveold = length(seen) > 0
	}
	/^## / {
		n++
		keep = haveold ? !(($0) in seen) : (n == 1)
	}
	n && keep { print }
' "$CHANGES")

# the "## Title" headings become "### Title" below the release title
if [ -n "$(echo "$notes" | tr -d '[:space:]')" ]; then
	echo "## Changes"
	echo
	echo "$notes" | sed 's/^## /### /'
	echo
else
	echo "No changes in $CHANGES since ${PREV:-the start}."
	echo
fi

owner=${REPO%%/*}
name=${REPO#*/}
cat <<EOF
## Images

Pick the image for your device with the
[firmware selector](https://$owner.github.io/$name/): download, SHA256 and
installation steps. Every image has a \`.manifest\` (package list) and
\`sha256sums-<variant>\`; \`SHA256SUMS\` covers them all.
Full change log: [$CHANGES](https://github.com/$REPO/blob/${GITHUB_REF_NAME:-nokvm}/$CHANGES)${PREV:+, changes since [$PREV](https://github.com/$REPO/compare/$PREV...${GITHUB_REF_NAME:-nokvm})}.
EOF
