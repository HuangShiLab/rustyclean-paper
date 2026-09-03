#!/bin/bash
# =============================================================================
# Normalise read IDs in existing ground_truth_labels.txt files
# =============================================================================
# The label files recorded the whole FASTQ header after the '@' -- description
# and mate suffix included -- while the accuracy scripts reduce a header to its
# first whitespace-delimited token with any /N or #N removed. Nothing ever
# matched, so every accuracy table came out precision 0, recall 0.
#
# The labels themselves are correct: the order and the microbe/host assignment
# come from the merge and are unaffected. Only the ID text is wrong, so the
# files can be rewritten in place rather than regenerating 540 M reads.
#
#   bash scripts/main/repair_ground_truth_labels.sh            # report only
#   bash scripts/main/repair_ground_truth_labels.sh --apply    # rewrite
# =============================================================================

set -euo pipefail

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$REPO_DIR/scripts/hpc/config.sh"

shopt -s nullglob
files=("$DATA_DIR"/*/ground_truth_labels.txt)
if [ ${#files[@]} -eq 0 ]; then
    echo "No label files under $DATA_DIR" >&2
    exit 1
fi

echo "Label files under $DATA_DIR: ${#files[@]}"
[ "$APPLY" -eq 1 ] || echo "(dry run — pass --apply to rewrite)"
echo

need=0
for f in "${files[@]}"; do
    ds=$(basename "$(dirname "$f")")
    first=$(head -n 1 "$f")
    id=${first%%$'\t'*}
    # Already normalised when the id carries no space and no mate suffix.
    if [[ "$id" != *" "* && "$id" != */* && "$id" != *"#"* ]]; then
        printf '  %-34s ok\n' "$ds"
        continue
    fi
    need=$((need + 1))
    clean=${id%%[[:space:]]*}; clean=${clean%%/*}; clean=${clean%%#*}
    printf '  %-34s %s  ->  %s\n' "$ds" "$id" "$clean"

    if [ "$APPLY" -eq 1 ]; then
        # Rewrite atomically: a half-written label file would be worse than the
        # unusable one it replaces, because its length would still look right.
        tmp="$f.repair.$$"
        awk -F'\t' 'BEGIN{OFS="\t"}
            { split($1, a, /[ \t]/); id=a[1]
              sub(/\/.*$/, "", id); sub(/#.*$/, "", id)
              print id, $2 }' "$f" > "$tmp"
        if [ "$(wc -l < "$tmp")" -ne "$(wc -l < "$f")" ]; then
            echo "ERROR: line count changed for $ds; leaving the original in place" >&2
            rm -f "$tmp"
            exit 1
        fi
        mv "$tmp" "$f"
    fi
done

echo
if [ "$need" -eq 0 ]; then
    echo "All label files already carry normalised IDs."
elif [ "$APPLY" -eq 1 ]; then
    echo "Rewrote $need file(s). Re-run the stage-6 accuracy jobs; no data needs regenerating."
else
    echo "$need file(s) need rewriting. Re-run with --apply."
fi
