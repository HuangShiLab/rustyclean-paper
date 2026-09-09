#!/bin/bash
# =============================================================================
# Measure a command's CPU and memory from the job's own cgroup
# =============================================================================
# Source this, do not execute it:
#
#     source "$REPO_DIR/scripts/hpc/cgroup_probe.sh"
#     cgroup_probe_init
#     cgroup_run "$time_log" mytool --args > "$log" 2>&1 || handle_failure
#     echo "$CG_CPU_SECONDS $CG_PEAK_ANON_KB $CG_PEAK_CURRENT_KB"
#
# WHY THIS EXISTS
#
# /usr/bin/time reports the rusage of the children it reaped and the peak RSS of
# the largest single process in that tree. Both are wrong here, in two different
# ways, and the parallel-scaling panel measured how wrong:
#
#   CPU     KneadData runs its real work in processes that chain does not
#           account for. GNU time saw 2,014 s where the cgroup saw 80,365 --
#           a factor of 40. Warming the page cache first left the GNU figure
#           unchanged to the second, which rules out I/O wait and leaves
#           undercounting.
#
#   MEMORY  Peak RSS is one process's footprint INCLUDING file-backed pages,
#           so a memory-mapped index counts even though every concurrent
#           process shares it. Hostile reads 3.57 GB by that measure and
#           0.21 GB of anonymous memory; RustyClean's survey reads 3.42 and
#           3.50, because its copy is private. The two numbers answer
#           different questions and only the anonymous one says how much RAM
#           it takes to run N of these at once.
#
# So: CPU comes from cpu.stat's usage_usec, memory from the peak of
# memory.stat's `anon`, both differenced across the command. memory.current is
# kept beside them because that is what sacct reports, and on this cluster it
# also counts reclaimable page cache -- roughly the size of the files read
# rather than a memory requirement.
#
# It is one file rather than a copy per benchmark on purpose. Two
# implementations of a measurement drift, and then the numbers they produce
# cannot be put in the same table.
# =============================================================================

CGROUP_PATH=""
CGROUP_OK=0
CGROUP_SAMPLE_INTERVAL="${CGROUP_SAMPLE_INTERVAL:-1}"

cgroup_probe_init() {
    local rel
    rel=$(awk -F: '$1=="0"{print $3} $2=="memory"{print $3}' /proc/self/cgroup 2>/dev/null | head -1 || true)
    CGROUP_PATH="/sys/fs/cgroup${rel}"
    if [ -r "$CGROUP_PATH/memory.stat" ]; then
        CGROUP_OK=1
        echo "  cgroup probe: $CGROUP_PATH (sampling every ${CGROUP_SAMPLE_INTERVAL}s)"
    else
        CGROUP_OK=0
        echo "  cgroup probe: $CGROUP_PATH is not readable; falling back to summing" >&2
        echo "                RSS over the process tree, which cannot see file-backed" >&2
        echo "                pages separately." >&2
    fi
}

cgroup_anon_bytes() {
    [ "$CGROUP_OK" = "1" ] || { echo 0; return; }
    awk '$1=="anon"{print $2; exit}' "$CGROUP_PATH/memory.stat" 2>/dev/null || echo 0
}

cgroup_current_bytes() {
    [ "$CGROUP_OK" = "1" ] || { echo 0; return; }
    cat "$CGROUP_PATH/memory.current" 2>/dev/null \
        || cat "$CGROUP_PATH/memory.usage_in_bytes" 2>/dev/null || echo 0
}

# Microseconds of CPU used by every process in the cgroup, however it was reaped.
cgroup_cpu_usec() {
    if [ -r "$CGROUP_PATH/cpu.stat" ]; then
        awk '$1=="usage_usec"{print $2; exit}' "$CGROUP_PATH/cpu.stat" 2>/dev/null
    elif [ -r "$CGROUP_PATH/cpuacct.usage" ]; then     # cgroup v1, nanoseconds
        awk '{printf "%d", $1/1000}' "$CGROUP_PATH/cpuacct.usage" 2>/dev/null
    fi
}

_cgroup_tree_rss_bytes() {   # fallback: sum RSS over a pid and its descendants
    ps -eo pid=,ppid=,rss= 2>/dev/null | awk -v root="$1" '
        { pid[NR]=$1; ppid[NR]=$2; rss[NR]=$3; n=NR }
        END { keep[root]=1
              for (pass=0; pass<24; pass++)
                  for (i=1;i<=n;i++) if (keep[ppid[i]]) keep[pid[i]]=1
              t=0; for (i=1;i<=n;i++) if (keep[pid[i]]) t+=rss[i]
              print t*1024 }'
}

# Append one sample per interval. Rewriting the file each time meant a read
# landing between the truncate and the write saw an empty file, and whole runs
# recorded no memory at all.
_cgroup_sampler_loop() {
    local out="$1" root="$2" a c
    while :; do
        if [ "$CGROUP_OK" = "1" ]; then
            a=$(cgroup_anon_bytes); c=$(cgroup_current_bytes)
        else
            a=$(_cgroup_tree_rss_bytes "$root"); c="$a"
        fi
        printf '%s %s\n' "${a:-0}" "${c:-0}" >> "$out"
        sleep "$CGROUP_SAMPLE_INTERVAL"
    done
}

# cgroup_run <timefile> <command...>
#
# Runs the command under /usr/bin/time -v (so the existing peak-RSS column keeps
# working) while sampling the cgroup. Returns the command's own exit status, so
# a caller's `|| { ... }` still fires. Sets:
#
#   CG_CPU_SECONDS      CPU seconds charged to the cgroup during the command
#   CG_PEAK_ANON_KB     peak anonymous memory across every process in the job
#   CG_PEAK_CURRENT_KB  peak memory.current, i.e. what sacct would report
#   CG_BASE_ANON_KB     anonymous memory before the command started
#
# Each is empty when the cgroup could not be read, so a caller can tell "not
# measured" from "measured as zero".
cgroup_run() {
    local timefile="$1"; shift
    local memfile="${timefile}.mem"
    local cpu_before cpu_after status=0

    : > "$memfile"
    CG_BASE_ANON_KB=""
    [ "$CGROUP_OK" = "1" ] && CG_BASE_ANON_KB=$(( $(cgroup_anon_bytes) / 1024 ))
    cpu_before=$(cgroup_cpu_usec)

    _cgroup_sampler_loop "$memfile" $$ &
    local sampler=$!

    /usr/bin/time -v -o "$timefile" "$@" || status=$?

    kill "$sampler" 2>/dev/null || true
    wait "$sampler" 2>/dev/null || true

    cpu_after=$(cgroup_cpu_usec)
    CG_CPU_SECONDS=""
    if [ -n "$cpu_before" ] && [ -n "$cpu_after" ]; then
        CG_CPU_SECONDS=$(awk -v a="$cpu_before" -v b="$cpu_after" \
                             'BEGIN{printf "%.2f", (b-a)/1000000}')
    fi

    CG_PEAK_ANON_KB=""
    CG_PEAK_CURRENT_KB=""
    if [ -s "$memfile" ]; then
        CG_PEAK_ANON_KB=$(awk 'BEGIN{m=0} {if ($1+0>m) m=$1+0} END{printf "%d", m/1024}' "$memfile")
        CG_PEAK_CURRENT_KB=$(awk 'BEGIN{m=0} {if ($2+0>m) m=$2+0} END{printf "%d", m/1024}' "$memfile")
    fi
    rm -f "$memfile"

    return "$status"
}
