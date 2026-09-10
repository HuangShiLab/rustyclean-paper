#!/bin/bash
# Install this repository's git hooks. Hooks live in .git/, which is not
# tracked, so they have to be copied in on each clone.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for hook in "$REPO"/scripts/git-hooks/*; do
    name="$(basename "$hook")"
    [ "$name" = "install.sh" ] && continue
    install -m 755 "$hook" "$REPO/.git/hooks/$name"
    echo "installed .git/hooks/$name"
done
