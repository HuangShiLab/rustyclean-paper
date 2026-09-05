#!/bin/bash
#SBATCH --job-name=rc_parallel_scaling
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --array=0-4
#SBATCH --cpus-per-task=16
#SBATCH --mem=200G
#SBATCH --exclusive
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

# =============================================================================
# Does RustyClean parallelise better than KneadData and Hostile?
# =============================================================================
#   sbatch scripts/main/benchmark_parallel_scaling.sh
#
# --exclusive is not an optimisation here, it is a precondition. Five array
# tasks are timing themselves at the same moment, and this partition has nodes
# wide enough to hold several of them; packed onto one node they would spend the
# run measuring each other. Dropping it would schedule sooner and measure
# nothing. The task is still bound to its 16 cores.
#
# Each array task is one point on the scaling curve. The task is given 16 cores
# and splits them as W workers x T threads with W*T = 16:
#
#     task 0 -> W=1  T=16      task 3 -> W=8  T=2
#     task 1 -> W=2  T=8       task 4 -> W=16 T=1
#     task 2 -> W=4  T=4
#
# Every tool runs the SAME 120 samples at that W on the SAME node, so the
# cross-tool comparison -- the thing being asked -- never crosses hardware.
# The curve across W does cross nodes; that is why W*T is held constant and why
# each arm's speed-up is computed against its own W=1 point rather than against
# another tool's.
#
# Five arms:
#
#   kneaddata                 trimmomatic + bowtie2, W processes under xargs
#   rustyclean_batch          fastp + auto, ONE process, --workers W
#   rustyclean_xargs          fastp + auto, W processes under xargs
#   hostile                   bowtie2 + samtools, W processes under xargs
#   rustyclean_batch_skipqc   no QC, ONE process, --workers W
#
# rustyclean_xargs is the control that makes the result mean anything. Without
# it, a RustyClean win could just be a faster aligner wrapper rather than better
# scheduling; comparing batch against xargs holds the tool fixed and varies only
# who does the scheduling. kneaddata and rustyclean_batch/_xargs all do read
# trimming; hostile and rustyclean_batch_skipqc both skip it.
#
# Before committing a node for 24 hours, check the wiring:
#
#   PARALLEL_DRY_RUN=1 bash scripts/main/benchmark_parallel_scaling.sh
#       builds the sample list, checks every tool and index, writes out the five
#       arm scripts and prints them. Runs nothing. Takes seconds, needs no node.
#
#   PARALLEL_LIMIT=6 sbatch --array=2 scripts/main/benchmark_parallel_scaling.sh
#       a real run of all five arms over 6 samples at W=4. This is the one that
#       matters: it proves each tool actually produces output where the
#       fingerprint step looks for it, which nothing else here can verify.
#
# NOTE ON BACKEND: at 1,000,000 reads every sample is below RustyClean's
# auto_reads_threshold (20M), so choose_auto_backend() returns bowtie2 for all
# six host fractions -- 90 % host included. That is deliberate here: all five
# arms then align against the same kind of index, and the measurement is of
# parallel efficiency rather than of which backend was picked. The survey still
# runs and still costs, and that cost is reported.
# =============================================================================

set -euo pipefail

if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
[ -n "${REPO_DIR:-}" ] || { echo "ERROR: cannot locate the repository. Set REPO_DIR." >&2; exit 1; }
source "$REPO_DIR/scripts/hpc/config.sh"
activate_conda
# kneaddata and hostile live in their own environments on this cluster.
export PATH="/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$HOME/.local/bin:$PATH"

CPUS="${SLURM_CPUS_PER_TASK:-$PARALLEL_CPUS}"
W_GRID=(1 2 4 8 16)
IDX="${SLURM_ARRAY_TASK_ID:-0}"
if [ "$IDX" -ge "${#W_GRID[@]}" ]; then
    echo "array task $IDX is past the end of the worker grid; nothing to do"; exit 0
fi
W="${W_GRID[$IDX]}"
if [ "$W" -gt "$CPUS" ]; then
    echo "W=$W exceeds the $CPUS cores this task holds; nothing to do"; exit 0
fi
T=$(( CPUS / W ))

ARMS_DEFAULT="kneaddata rustyclean_batch rustyclean_xargs hostile rustyclean_batch_skipqc"
read -r -a ARMS <<< "${PARALLEL_ARMS:-$ARMS_DEFAULT}"

RUNS_BASE="$PARALLEL_RUNS_DIR"
if [ -n "${PARALLEL_LIMIT:-}" ]; then
    # A 6-sample run and a 120-sample run write the same file names. Keeping the
    # smoke test in its own tree means it cannot end up averaged into the real
    # curve, and the real run does not have to be told to clean up after it.
    RUNS_BASE="${PARALLEL_RUNS_DIR}_smoke"
fi
RUN_ROOT="$RUNS_BASE/W${W}"
METRICS_DIR="$RUNS_BASE/metrics"
LOGS_ROOT="$RUN_ROOT/logs"
mkdir -p "$RUN_ROOT" "$METRICS_DIR" "$LOGS_ROOT"

# Own file per array task: concurrent appends to one CSV interleave under a
# single header. scripts/main/collect_resources.py merges the parts.
METRICS="$METRICS_DIR/parallel_scaling.task${IDX}.csv"
echo "arm,workers,threads,cpus,n_samples,n_failed,wall_seconds,user_seconds,sys_seconds,cpu_efficiency,samples_per_hour,peak_rss_kb,peak_anon_kb,peak_cgroup_kb,baseline_anon_kb,runtime_seconds,max_memory_kb,node,timestamp" > "$METRICS"

echo "==============================================================="
echo " parallel scaling — W=$W workers x T=$T threads on $CPUS cores"
echo " node:  $(hostname)"
echo " arms:  ${ARMS[*]}"
echo " start: $(date -Iseconds)"
echo "==============================================================="

# ---------------------------------------------------------------------------
# Sample list
# ---------------------------------------------------------------------------
READS_DIR="$PARALLEL_DATA_DIR/reads"
N_EXPECTED=$(( $(wc -w <<< "$PARALLEL_HOST_PCTS") * PARALLEL_N_REPS ))
ALL_READS=()
[ -d "$READS_DIR" ] && mapfile -t ALL_READS < <(find "$READS_DIR" -maxdepth 1 -name '*.fastq.gz' | sort)

if [ "${PARALLEL_DRY_RUN:-0}" = "1" ] && [ "${#ALL_READS[@]}" -eq 0 ]; then
    # The point of the preflight is to find a missing tool or index BEFORE
    # spending a day simulating reads for it, so it must not require the reads.
    echo "  NOTE: no panel at $READS_DIR yet; using the names it will have."
    for _p in $PARALLEL_HOST_PCTS; do
        for _r in $(seq 1 "$PARALLEL_N_REPS"); do
            ALL_READS+=("$READS_DIR/h$(printf '%02d' "$_p")_r$(printf '%02d' "$_r").fastq.gz")
        done
    done
elif [ ! -d "$READS_DIR" ]; then
    echo "ERROR: no panel at $READS_DIR. Run generate_parallel_data.sh first." >&2
    exit 1
fi

if [ -n "${PARALLEL_LIMIT:-}" ]; then
    echo "  NOTE: PARALLEL_LIMIT=$PARALLEL_LIMIT — this is a smoke test, not a measurement."
elif [ "${#ALL_READS[@]}" -ne "$N_EXPECTED" ]; then
    echo "ERROR: found ${#ALL_READS[@]} samples, expected $N_EXPECTED." >&2
    echo "       A short panel makes the batch times incomparable between arms." >&2
    echo "       Check which generate_parallel_data.sh array tasks failed." >&2
    exit 1
fi

# ONE fixed order for every arm and every W. The panel spans 1 % to 90 % host,
# so samples do not all cost the same; processing them in sorted order would put
# every expensive sample in the final chunk and give whichever arm ran last a
# different tail. Shuffle once, with a fixed seed, and reuse.
SAMPLES_TSV="$RUN_ROOT/samples.tsv"     # id <tab> r1   (rustyclean --samples)
SAMPLES_LIST="$RUN_ROOT/samples.list"   # id space r1   (xargs -n 2)
printf '%s\n' "${ALL_READS[@]}" \
  | shuf --random-source=<(yes "rustyclean-parallel-order") \
  | awk -F/ '{ id=$NF; sub(/\.fastq\.gz$/, "", id); print id "\t" $0 }' > "$SAMPLES_TSV"
if [ -n "${PARALLEL_LIMIT:-}" ]; then
    head -n "$PARALLEL_LIMIT" "$SAMPLES_TSV" > "$SAMPLES_TSV.tmp" && mv "$SAMPLES_TSV.tmp" "$SAMPLES_TSV"
fi
awk -F'\t' '{print $1, $2}' "$SAMPLES_TSV" > "$SAMPLES_LIST"
N_SAMPLES=$(wc -l < "$SAMPLES_TSV")
# xargs -n 2 splits on whitespace, so a space anywhere in an id or a path would
# hand the worker two halves of one filename instead of an (id, path) pair.
if awk 'NF != 2 { exit 1 }' "$SAMPLES_LIST"; then :; else
    echo "ERROR: a sample id or path contains a space; xargs -n 2 would split it." >&2
    awk 'NF != 2' "$SAMPLES_LIST" >&2
    exit 1
fi
echo "  $N_SAMPLES samples, fixed shuffled order -> $SAMPLES_TSV"

# ---------------------------------------------------------------------------
# Where the arms write
# ---------------------------------------------------------------------------
# KneadData writes its cleaned FASTQ uncompressed, so one arm can hold ~40 GB.
# Node-local scratch keeps that off the shared filesystem, which matters here
# more than usual: five array tasks are timing themselves at once, and if they
# all write to lustre the contention lands inside the numbers being measured.
# Fall back to the project filesystem when the node has no room, and say so, so
# a slow curve can be attributed rather than puzzled over.
need_gb=80
avail_gb=0
mkdir -p "$LOCAL_SCRATCH" 2>/dev/null || true
if [ -d "$LOCAL_SCRATCH" ]; then
    avail_gb=$(df -BG --output=avail "$LOCAL_SCRATCH" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
fi
if [ "${avail_gb:-0}" -ge "$need_gb" ]; then
    WORK_ROOT="$LOCAL_SCRATCH/parallel_W${W}"
    echo "  arm output -> node-local scratch ($avail_gb GB free)"
else
    WORK_ROOT="$RUN_ROOT/work"
    echo "  WARNING: node-local scratch has ${avail_gb} GB, need $need_gb; writing arm"
    echo "           output to $WORK_ROOT on the shared filesystem instead. Shared-FS"
    echo "           contention between the concurrent array tasks may inflate the"
    echo "           wall times recorded here."
fi
mkdir -p "$WORK_ROOT"
trap 'rm -rf "$WORK_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Memory sampling
# ---------------------------------------------------------------------------
# /usr/bin/time reports the peak RSS of the largest single process in the tree,
# which is the wrong quantity here: the question is how much memory it takes to
# run W of them at once. Sample the job's own cgroup instead and keep the peak
# of memory.stat's `anon`, which is the anonymous (non-reclaimable) total across
# every process in the job. memory.current is kept alongside it because that is
# what sacct reports, and on this cluster it also counts reclaimable page cache
# -- roughly the size of the FASTQ files read, not a memory requirement.
CG_REL=$(awk -F: '$1=="0"{print $3} $2=="memory"{print $3}' /proc/self/cgroup 2>/dev/null | head -1 || true)
CG="/sys/fs/cgroup${CG_REL}"
if [ -r "$CG/memory.stat" ]; then
    echo "  memory: sampling this job's cgroup $CG every ${PARALLEL_MEM_INTERVAL}s"
    HAVE_CGROUP=1
else
    echo "  memory: cgroup unreadable; falling back to summing RSS over the process tree"
    HAVE_CGROUP=0
fi

if command -v pigz >/dev/null 2>&1; then GUNZIP="pigz -dc"; else GUNZIP="gzip -dc"; fi

tree_rss_bytes() {   # sum RSS over a pid and every descendant
    ps -eo pid=,ppid=,rss= 2>/dev/null | awk -v root="$1" '
        { pid[NR]=$1; ppid[NR]=$2; rss[NR]=$3; n=NR }
        END { keep[root]=1
              for (pass=0; pass<24; pass++)
                  for (i=1;i<=n;i++) if (keep[ppid[i]]) keep[pid[i]]=1
              t=0; for (i=1;i<=n;i++) if (keep[pid[i]]) t+=rss[i]
              print t*1024 }'
}

read_anon()    { awk '$1=="anon"{print $2; exit}' "$CG/memory.stat" 2>/dev/null || echo 0; }
read_current() { cat "$CG/memory.current" 2>/dev/null || cat "$CG/memory.usage_in_bytes" 2>/dev/null || echo 0; }

sampler_loop() {    # sampler_loop <outfile> <root_pid>
    local out="$1" root="$2" pa=0 pc=0 a c
    while :; do
        if [ "$HAVE_CGROUP" = "1" ]; then
            a=$(read_anon); c=$(read_current)
        else
            a=$(tree_rss_bytes "$root"); c="$a"
        fi
        [ -n "$a" ] || a=0
        [ -n "$c" ] || c=0
        if [ "$a" -gt "$pa" ] 2>/dev/null; then pa="$a"; fi
        if [ "$c" -gt "$pc" ] 2>/dev/null; then pc="$c"; fi
        printf '%s %s\n' "$pa" "$pc" > "$out"
        sleep "$PARALLEL_MEM_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# One measured arm
# ---------------------------------------------------------------------------
# Each arm is written out as a real script before it runs, so what was measured
# can be read back afterwards instead of reconstructed from this file.
measure_arm() {
    local arm="$1" driver="$2"
    local out_dir="$WORK_ROOT/$arm" log_dir="$LOGS_ROOT/$arm"
    rm -rf "$out_dir"; mkdir -p "$out_dir" "$log_dir"
    rm -f "$log_dir/failures.txt"

    local timefile="$log_dir/arm.time" memfile="$log_dir/arm.mem"
    local baseline_anon=0
    [ "$HAVE_CGROUP" = "1" ] && baseline_anon=$(read_anon)

    echo
    echo "--- $arm  (W=$W, T=$T) ---"
    printf '  started %s\n' "$(date -Iseconds)"

    printf '0 0\n' > "$memfile"
    sampler_loop "$memfile" $$ &
    local sampler=$!

    local status=ok
    /usr/bin/time -v -o "$timefile" bash "$driver" > "$log_dir/arm.log" 2>&1 || status=FAILED
    kill "$sampler" 2>/dev/null || true
    wait "$sampler" 2>/dev/null || true

    local wall user sys rss
    wall=$(awk -F': ' '/Elapsed \(wall clock\)/{print $NF}' "$timefile" | awk -F: '
        { if (NF==3) printf "%.2f", $1*3600+$2*60+$3;
          else if (NF==2) printf "%.2f", $1*60+$2;
          else printf "%.2f", $1 }')
    user=$(awk -F': ' '/User time \(seconds\)/{print $NF}' "$timefile")
    sys=$(awk -F': ' '/System time \(seconds\)/{print $NF}' "$timefile")
    rss=$(awk -F': ' '/Maximum resident set size/{print $NF}' "$timefile")
    local peak_anon peak_cur
    peak_anon=$(awk '{print $1+0}' "$memfile" | tail -1)
    peak_cur=$(awk '{print $2+0}' "$memfile" | tail -1)
    [ -n "$wall" ] || wall=0
    [ -n "$user" ] || user=0
    [ -n "$sys" ]  || sys=0
    [ -n "$rss" ]  || rss=0
    [ -n "$peak_anon" ] || peak_anon=0
    [ -n "$peak_cur" ]  || peak_cur=0

    # For an xargs arm this counts samples; a batch arm is one process, so it is
    # 0 or 1 there and the per-sample picture comes from the MISSING rows in the
    # fingerprint file instead.
    local failed=0
    [ -f "$log_dir/failures.txt" ] && failed=$(wc -l < "$log_dir/failures.txt")

    local eff sph
    eff=$(awk -v u="$user" -v s="$sys" -v w="$wall" -v c="$CPUS" \
              'BEGIN{ if (w>0 && c>0) printf "%.4f", (u+s)/(w*c) }')
    sph=$(awk -v n="$N_SAMPLES" -v w="$wall" \
              'BEGIN{ if (w>0) printf "%.2f", n*3600.0/w }')

    # runtime_seconds and max_memory_kb repeat wall_seconds and peak_anon under
    # the names collect_resources.py looks for, so this experiment shows up in
    # the panel-wide resource table without teaching that script a new schema.
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$arm" "$W" "$T" "$CPUS" "$N_SAMPLES" "$failed" \
        "$wall" "$user" "$sys" "$eff" "$sph" \
        "$rss" "$((peak_anon / 1024))" "$((peak_cur / 1024))" "$((baseline_anon / 1024))" \
        "$wall" "$((peak_anon / 1024))" "$(hostname)" "$(date -Iseconds)" >> "$METRICS"

    printf '  %-24s wall %8.0fs  cpu-eff %5s  peak-anon %6.1f GB  failed %s\n' \
        "$arm" "$wall" "$eff" "$(awk -v b="$peak_anon" 'BEGIN{printf "%.1f", b/1073741824}')" "$failed"
    [ "$status" = "ok" ] || echo "  NOTE: the driver itself exited non-zero; see $log_dir/arm.log" >&2

    fingerprint_arm "$arm" "$out_dir"
    rm -rf "$out_dir"
}

# ---------------------------------------------------------------------------
# What each arm actually produced
# ---------------------------------------------------------------------------
# Retained-read count per sample, recorded after every arm and every W. A
# concurrency bug shows up here and nowhere else: batch wall time would look
# fine while the output quietly differed from the W=1 run. Counts must match
# across W within an arm, and rustyclean_batch must match rustyclean_xargs
# exactly. Set PARALLEL_DIGEST=1 to also compare the read-id sets, which is
# stronger and much slower.
fingerprint_arm() {
    local arm="$1" out_dir="$2"
    local fp="$METRICS_DIR/fingerprint_W${W}_${arm}.tsv"
    echo -e "sample_id\tretained_reads\tid_digest" > "$fp"

    local sid clean n digest
    while read -r sid _; do
        case "$arm" in
            kneaddata) clean=$(find "$out_dir/$sid" -name '*kneaddata.fastq' ! -name '*contam*' 2>/dev/null | head -1) ;;
            hostile)   clean=$(find "$out_dir/$sid" -name '*clean*.fastq.gz' 2>/dev/null | head -1) ;;
            *)         clean=$(find "$out_dir/$sid" -name '*_clean_R1.fastq.gz' 2>/dev/null | head -1) ;;
        esac
        if [ -z "$clean" ] || [ ! -s "$clean" ]; then
            printf '%s\tMISSING\t\n' "$sid" >> "$fp"; continue
        fi
        case "$clean" in
            *.gz) n=$(( $($GUNZIP "$clean" | wc -l) / 4 )) ;;
            *)    n=$(( $(wc -l < "$clean") / 4 )) ;;
        esac
        digest=""
        if [ "${PARALLEL_DIGEST:-0}" = "1" ]; then
            # if/else rather than a case: a case pattern's ")" inside $( ) trips
            # bash's command-substitution parser.
            digest=$(if [ "${clean%.gz}" != "$clean" ]; then $GUNZIP "$clean"; else cat "$clean"; fi \
                | awk 'NR%4==1{id=substr($1,2); sub(/\/.*$/,"",id); sub(/#.*$/,"",id); print id}' \
                | LC_ALL=C sort -S 512M | cksum | awk '{print $1}')
        fi
        printf '%s\t%s\t%s\n' "$sid" "$n" "$digest" >> "$fp"
    done < "$SAMPLES_LIST"
    echo "  fingerprint -> $fp"
}

# ---------------------------------------------------------------------------
# The arms
# ---------------------------------------------------------------------------
write_driver() {   # write_driver <arm>; echoes the driver path
    local arm="$1"
    local d="$LOGS_ROOT/$arm" worker="$LOGS_ROOT/$arm/worker.sh" driver="$LOGS_ROOT/$arm/driver.sh"
    mkdir -p "$d"

    case "$arm" in
    kneaddata)
        cat > "$worker" <<'EOF'
#!/bin/bash
sid="$1"; r1="$2"
mkdir -p "$ARM_OUT/$sid"
kneaddata -un "$r1" -db "$KNEADDATA_DB" -o "$ARM_OUT/$sid" -t "$T" \
    --remove-intermediate-output > "$ARM_LOG/$sid.log" 2>&1 \
    || echo "$sid" >> "$ARM_LOG/failures.txt"
EOF
        ;;
    hostile)
        cat > "$worker" <<'EOF'
#!/bin/bash
sid="$1"; r1="$2"
mkdir -p "$ARM_OUT/$sid"
hostile clean --fastq1 "$r1" --aligner bowtie2 --index "$HOSTILE_INDEX" --airplane \
    --output "$ARM_OUT/$sid" --threads "$T" --force > "$ARM_LOG/$sid.log" 2>&1 \
    || echo "$sid" >> "$ARM_LOG/failures.txt"
EOF
        ;;
    rustyclean_xargs)
        # A one-line sample list rather than --r1. With --r1 the sample id comes
        # from the PARENT DIRECTORY name (sample.rs:97), and this panel is a flat
        # directory, so all 120 processes would call themselves "reads" and write
        # over each other. Each process also needs its own checkpoint directory:
        # the default is a fixed path in the working directory, which 120
        # concurrent processes would share.
        cat > "$worker" <<'EOF'
#!/bin/bash
sid="$1"; r1="$2"
mkdir -p "$ARM_OUT/$sid"
one="$ARM_LOG/$sid.tsv"
printf '%s\t%s\n' "$sid" "$r1" > "$one"
# -o "$ARM_OUT" with the id supplied by the list puts output at exactly the same
# path the batch arm uses, so the two fingerprints can be compared read for read.
"$RUSTYCLEAN" --samples "$one" --mode auto --auto-survey \
    --host-index "$BOWTIE2_INDEX" --kraken2-db "$KRAKEN2_DB" \
    --max-contamination 100.0 -o "$ARM_OUT" -t "$T" -w 1 \
    --checkpoint-dir "$ARM_LOG/ckpt/$sid" --clean \
    > "$ARM_LOG/$sid.log" 2>&1 || echo "$sid" >> "$ARM_LOG/failures.txt"
EOF
        ;;
    esac

    case "$arm" in
    rustyclean_batch|rustyclean_batch_skipqc)
        local skip=""
        [ "$arm" = "rustyclean_batch_skipqc" ] && skip="--skip-qc"
        cat > "$driver" <<EOF
#!/bin/bash
# One process, RustyClean's own worker pool: --workers $W, --threads $T.
"\$RUSTYCLEAN" --samples "\$SAMPLES_TSV" --mode auto --auto-survey \\
    --host-index "\$BOWTIE2_INDEX" --kraken2-db "\$KRAKEN2_DB" \\
    --max-contamination 100.0 $skip \\
    -o "\$ARM_OUT" -w $W -t $T \\
    --checkpoint-dir "\$ARM_OUT/.checkpoints" --clean \\
    > "\$ARM_LOG/batch.log" 2>&1 || echo "batch" >> "\$ARM_LOG/failures.txt"
EOF
        ;;
    *)
        cat > "$driver" <<EOF
#!/bin/bash
# $W independent processes, parallelised from the shell exactly as a user would.
xargs -a "\$SAMPLES_LIST" -P $W -n 2 bash "$worker"
EOF
        ;;
    esac
    chmod +x "$driver" 2>/dev/null || true
    [ -f "$worker" ] && chmod +x "$worker" 2>/dev/null || true
    echo "$driver"
}

export RUSTYCLEAN KNEADDATA_DB HOSTILE_INDEX BOWTIE2_INDEX KRAKEN2_DB
export SAMPLES_TSV SAMPLES_LIST T

# An arm whose tool or reference is missing must be reported as absent, not
# silently left out of the comparison: a scaling curve with one arm quietly
# missing reads as a result rather than as a gap.
arm_ready() {
    case "$1" in
        kneaddata)
            command -v kneaddata >/dev/null 2>&1 || { echo "not on PATH"; return 1; }
            [ -d "$KNEADDATA_DB" ] || { echo "database missing: $KNEADDATA_DB"; return 1; } ;;
        hostile)
            command -v hostile >/dev/null 2>&1 || { echo "not on PATH"; return 1; }
            [ -e "${HOSTILE_INDEX}.1.bt2" ] || [ -e "${HOSTILE_INDEX}.1.bt2l" ] \
                || { echo "index missing: $HOSTILE_INDEX"; return 1; } ;;
        rustyclean_*)
            [ -x "$RUSTYCLEAN" ] || { echo "binary not executable: $RUSTYCLEAN"; return 1; }
            [ -e "${BOWTIE2_INDEX}.1.bt2" ] || [ -e "${BOWTIE2_INDEX}.1.bt2l" ] \
                || { echo "bowtie2 index missing: $BOWTIE2_INDEX"; return 1; } ;;
    esac
    return 0
}

for arm in "${ARMS[@]}"; do
    if ! reason=$(arm_ready "$arm"); then
        echo "SKIP $arm: $reason" >&2
        printf '%s,%s,%s,%s,%s,,,,,,,,,,,SKIPPED,,%s,%s\n' \
            "$arm" "$W" "$T" "$CPUS" "$N_SAMPLES" "$(hostname)" "$(date -Iseconds)" >> "$METRICS"
        continue
    fi
    export ARM_OUT="$WORK_ROOT/$arm" ARM_LOG="$LOGS_ROOT/$arm"
    driver=$(write_driver "$arm")
    if [ "${PARALLEL_DRY_RUN:-0}" = "1" ]; then
        echo; echo "--- $arm (dry run) ---"; echo "  driver: $driver"
        sed 's/^/    /' "$driver"
        [ -f "$LOGS_ROOT/$arm/worker.sh" ] && { echo "  worker:"; sed 's/^/    /' "$LOGS_ROOT/$arm/worker.sh"; }
        continue
    fi
    measure_arm "$arm" "$driver"
done

if [ "${PARALLEL_DRY_RUN:-0}" = "1" ]; then
    echo; echo "dry run: nothing was executed. $N_SAMPLES samples would run at W=$W, T=$T."
    exit 0
fi

echo
echo "==============================================================="
echo " finished $(date -Iseconds)"
echo " metrics: $METRICS"
echo "==============================================================="
