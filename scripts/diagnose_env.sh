#!/bin/bash
# =============================================================================
# Diagnose why a tool cannot be installed, and find it if it already exists
# =============================================================================
#   bash scripts/diagnose_env.sh [tool ...]     (default: art_illumina iss)
# =============================================================================

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/scripts/hpc/config.sh" 2>/dev/null
set +euo pipefail
TOOLS=("${@:-art_illumina}")
[ $# -eq 0 ] && TOOLS=(art_illumina iss)

echo "=== 1. Proxy configuration ==="
found=0
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy; do
    val=$(eval echo "\${$v:-}")
    [ -n "$val" ] && { printf "  %-14s %s\n" "$v" "$val"; found=1; }
done
[ "$found" -eq 0 ] && echo "  no *_proxy variables set in this shell"
for rc in "$HOME/.condarc" "$CONDA_BASE/.condarc"; do
    [ -f "$rc" ] && grep -qi proxy "$rc" && { echo "  proxy settings in $rc:"; grep -i -A3 proxy "$rc" | sed 's/^/    /'; }
done

echo
echo "=== 2. Can anything reach the network? ==="
for probe in "conda.anaconda.org:443" "pypi.org:443"; do
    host=${probe%:*}; port=${probe#*:}
    timeout 6 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null \
        && echo "  reachable   $probe" || echo "  UNREACHABLE $probe"
done

echo
echo "=== 3. Module system ==="
if command -v module >/dev/null 2>&1; then
    echo "  module command available; searching for the tools..."
    for t in "${TOOLS[@]}"; do
        out=$(module avail "$t" 2>&1 | grep -vE "^-|^$" | head -3)
        [ -n "$out" ] && printf "    %-14s %s\n" "$t" "$out" || printf "    %-14s no module found\n" "$t"
    done
else
    echo "  no module command on this host"
fi

echo
echo "=== 4. Is the tool already on the filesystem? ==="
for t in "${TOOLS[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
        printf "  %-14s on PATH: %s\n" "$t" "$(command -v "$t")"
        continue
    fi
    hits=$(find "$CONDA_BASE/envs" "$PROJECT_DIR/.conda_envs" "$HOME/.conda/envs" \
                /lustre1/g/aos_shihuang/tools -maxdepth 4 -name "$t" -type f 2>/dev/null | head -3)
    if [ -n "$hits" ]; then
        printf "  %-14s found, not on PATH:\n" "$t"
        printf "%s\n" "$hits" | sed 's/^/      /'
        printf "      add with: export PATH=%s:$PATH\n" "$(dirname "$(printf "%s" "$hits" | head -1)")"
    else
        printf "  %-14s not found anywhere searched\n" "$t"
    fi
done

echo
echo "=== 5. Existing conda environments ==="
ls -1d "$CONDA_BASE"/envs/*/ "$PROJECT_DIR"/.conda_envs/*/ "$HOME"/.conda/envs/*/ 2>/dev/null \
    | sed 's#/$##;s#.*/#  #' | sort -u | head -30

echo
echo "-------------------------------------------------------------"
echo "If the network is unreachable, options are, in order of effort:"
echo "  1. set the cluster's proxy, then retry conda"
echo "  2. load the tool from the module system if section 3 found one"
echo "  3. put an existing install on PATH if section 4 found one"
echo "  4. install on a host with network access into \$PROJECT_DIR/.conda_envs,"
echo "     which is on shared storage and visible from the compute nodes"
