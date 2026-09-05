#!/bin/bash
#SBATCH --job-name=rc_parallel_gen
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --array=1-20
#SBATCH --cpus-per-task=16
#SBATCH --mem=48G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

# =============================================================================
# Simulate the parallel-scaling panel: 120 uniform single-end samples
# =============================================================================
#   sbatch scripts/main/generate_parallel_data.sh
#
# 6 host fractions (1, 5, 10, 50, 70, 90 %) x 20 replicates = 120 samples, each
# exactly 1,000,000 reads of 151 bp, one .fastq.gz per sample in a flat
# directory. Uniform depth is the point: batch wall time then measures how well
# a tool keeps 16 cores busy, not which sample happened to be the big one.
#
# One array task per replicate. Each task makes all six host fractions for its
# replicate from TWO InSilicoSeq runs -- one microbial, one host -- and cuts
# DISJOINT slices out of them. Six separate ISS invocations per replicate would
# reload the 3.1 Gbp human genome six times for no benefit; slicing one run
# keeps the samples independent (no read appears in two samples) while paying
# the genome load once.
#
# Reruns: a replicate that already carries .rep<NN>.done is skipped unless the
# recorded ISS model or seed differs from the current settings, in the same way
# generate_data_slurm.sh checks metadata.json. FORCE_REGEN=1 rebuilds anyway.
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

ISS_BIN=$(resolve_tool "$ISS" "iss")
CPUS="${SLURM_CPUS_PER_TASK:-16}"
REP=$(printf '%02d' "${SLURM_ARRAY_TASK_ID:-1}")

read -r -a HOST_PCTS <<< "$PARALLEL_HOST_PCTS"
READS="$PARALLEL_READS_PER_SAMPLE"

# --array in the directives above is literal -- SLURM parses it before any shell
# runs -- so it cannot follow PARALLEL_N_REPS. Lowering the variable without
# lowering the array would leave extra tasks writing replicates the benchmark
# never expects; raising it without raising the array would leave gaps, and the
# benchmark refuses to run on a short panel.
if [ "${SLURM_ARRAY_TASK_ID:-1}" -gt "$PARALLEL_N_REPS" ]; then
    echo "task ${SLURM_ARRAY_TASK_ID} is past PARALLEL_N_REPS=$PARALLEL_N_REPS; nothing to do"
    exit 0
fi
N_SPECIES="$PARALLEL_N_SPECIES"

OUT_DIR="$PARALLEL_DATA_DIR/reads"
LABEL_DIR="$PARALLEL_DATA_DIR/labels"
MANIFEST_DIR="$PARALLEL_DATA_DIR/manifest"
mkdir -p "$OUT_DIR" "$LABEL_DIR" "$MANIFEST_DIR" "$LOG_DIR/parallel_gen"

DONE_FLAG="$PARALLEL_DATA_DIR/.rep${REP}.done"
STAMP="model=${ISS_MODEL} seed_base=${SIM_SEED} reads=${READS} pcts=${PARALLEL_HOST_PCTS} species=${N_SPECIES}"

if [ "${FORCE_REGEN:-0}" != "1" ] && [ -f "$DONE_FLAG" ]; then
    if [ "$(cat "$DONE_FLAG")" = "$STAMP" ]; then
        echo "[rep $REP] already generated with the current settings; skipping."
        exit 0
    fi
    echo "[rep $REP] existing data was built with different settings; regenerating." >&2
    echo "  was: $(cat "$DONE_FLAG")" >&2
    echo "  now: $STAMP" >&2
    rm -f "$DONE_FLAG"
fi

echo "[rep $REP] host fractions: ${HOST_PCTS[*]}  |  ${READS} reads/sample  |  start $(date -Iseconds)"

WORKDIR="$LOCAL_SCRATCH/parallel_rep${REP}"
rm -rf "$WORKDIR"; mkdir -p "$WORKDIR"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Per-fraction read counts, and the totals the two ISS runs must cover
# ---------------------------------------------------------------------------
HOST_N=(); MICROBE_N=(); SAMPLE_IDS=()
host_total=0; microbe_total=0
for pct in "${HOST_PCTS[@]}"; do
    h=$(python3 -c "print(int(round($READS * $pct / 100.0)))")
    m=$((READS - h))
    HOST_N+=("$h"); MICROBE_N+=("$m")
    SAMPLE_IDS+=("h$(printf '%02d' "$pct")_r${REP}")
    host_total=$((host_total + h))
    microbe_total=$((microbe_total + m))
done
echo "  slices: host ${HOST_N[*]} (total $host_total) | microbe ${MICROBE_N[*]} (total $microbe_total)"

# ---------------------------------------------------------------------------
# Reference sequence
# ---------------------------------------------------------------------------
HUMAN_FASTA="$WORKDIR/human.fasta"
if [ ! -f "$HUMAN_GENOME" ]; then
    echo "ERROR: human genome not found at $HUMAN_GENOME" >&2; exit 1
fi
case "$HUMAN_GENOME" in
    *.gz) gunzip -c "$HUMAN_GENOME" > "$HUMAN_FASTA" ;;
    *)    cp "$HUMAN_GENOME" "$HUMAN_FASTA" ;;
esac

MICROBE_SRC="${MICROBIAL_GENOME_DIR:-$GENOME_DIR/genomes_fasta}"
[ -d "$MICROBE_SRC" ] || { echo "ERROR: microbial genomes not found: $MICROBE_SRC" >&2; exit 1; }
mapfile -t all_genomes < <(find "$MICROBE_SRC" -maxdepth 1 \
    \( -name '*.fasta' -o -name '*.fa' -o -name '*.fna' \
       -o -name '*.fasta.gz' -o -name '*.fa.gz' -o -name '*.fna.gz' \) | sort)
[ "${#all_genomes[@]}" -gt 0 ] || { echo "ERROR: no genomes in $MICROBE_SRC" >&2; exit 1; }

# A distinct community per replicate, so the 20 replicates of a host fraction
# are 20 different metagenomes rather than 20 redraws of one. The seed is the
# replicate id, so the draw is reproducible.
SAMPLE_SEED="rustyclean-parallel-rep${REP}"
mapfile -t picked < <(printf '%s\n' "${all_genomes[@]}" \
    | shuf -n "$N_SPECIES" --random-source=<(yes "$SAMPLE_SEED"))

# Host sequence hiding in the microbial pool would be labelled microbial while
# genuinely being host, which silently inverts part of the ground truth.
if printf '%s\n' "${picked[@]}" \
     | grep -Eiq 'human|homo_?sapiens|GRCh3[78]|chm13|hg19|hg38|T2T|GCF_009914755|GCF_000001405'; then
    echo "ERROR: the sampled community contains what looks like a human genome:" >&2
    printf '%s\n' "${picked[@]}" \
      | grep -Ei 'human|homo_?sapiens|GRCh3[78]|chm13|hg19|hg38|T2T|GCF_009914755|GCF_000001405' >&2
    exit 1
fi

MICROBIAL_FA="$WORKDIR/microbial.fasta"
: > "$MICROBIAL_FA"
for g in "${picked[@]}"; do
    case "$g" in *.gz) zcat "$g" >> "$MICROBIAL_FA" ;; *) cat "$g" >> "$MICROBIAL_FA" ;; esac
done
printf '%s\n' "${picked[@]}" > "$MANIFEST_DIR/community_rep${REP}.txt"
echo "  community: $N_SPECIES genomes sampled from ${#all_genomes[@]} (seed=$SAMPLE_SEED)"

# ---------------------------------------------------------------------------
# Abundance profile: drawn per genome, then split across that genome's contigs
# in proportion to length, which is what uniform coverage of a draft assembly
# produces. Keying it per record would weight a 200-contig draft 200x a closed
# genome.
# ---------------------------------------------------------------------------
ABUNDANCE_FILE="$WORKDIR/abundance.txt"
python3 - "$MANIFEST_DIR/community_rep${REP}.txt" "$ABUNDANCE_FILE" "$REP" <<'PYEOF'
import gzip, sys
import numpy as np

manifest, out, rep = sys.argv[1:4]
np.random.seed(1000 + int(rep))
genomes = [l.strip() for l in open(manifest) if l.strip()]

def records(path):
    opener = gzip.open if path.endswith(".gz") else open
    out, rid, length = [], None, 0
    with opener(path, "rt") as fh:
        for line in fh:
            if line.startswith(">"):
                if rid is not None:
                    out.append((rid, length))
                rid, length = line[1:].split()[0], 0
            else:
                length += len(line.strip())
    if rid is not None:
        out.append((rid, length))
    return out

per_genome = [records(g) for g in genomes]
ab = np.random.lognormal(0, 2, len(per_genome))
ab = ab / ab.sum()

rows = []
for a, recs in zip(ab, per_genome):
    total = sum(n for _, n in recs)
    if total == 0:
        continue
    for rid, n in recs:
        rows.append((rid, a * n / total))
if not rows:
    sys.exit("ERROR: no sequence records in the sampled community")
scale = sum(a for _, a in rows)
with open(out, "w") as fh:
    for rid, a in rows:
        fh.write("%s\t%.10f\n" % (rid, a / scale))
print("  abundance: %d records across %d genomes" % (len(rows), len(per_genome)))
PYEOF

# ---------------------------------------------------------------------------
# Two ISS runs
# ---------------------------------------------------------------------------
# ISS always writes paired output: --n_reads N puts about N/2 records in each of
# _R1 and _R2. These are single-end samples and keep R1 only, so ask for twice
# what the slices need. The extra 1 % is slack: ISS rounds per record and can
# land a little either side of the request, and coming up short would silently
# truncate the last slice.
iss_request() { python3 -c "print(int($1 * 2 * 1.01) + 1000)"; }

ISS_HELP="$("$ISS_BIN" generate --help 2>&1 || true)"
case "$ISS_HELP" in
    *--seed*) : ;;
    *) echo "ERROR: this InSilicoSeq build has no --seed; the panel could not be" >&2
       echo "       regenerated. Install a newer InSilicoSeq." >&2; exit 1 ;;
esac
SEED=$(( ${SIM_SEED:-42} + ${SLURM_ARRAY_TASK_ID:-1} ))
echo "  ISS seed: $SEED  model: ${ISS_MODEL}"

echo "  [1/2] microbial reads ($(iss_request "$microbe_total") requested)..."
"$ISS_BIN" generate \
    --genomes "$MICROBIAL_FA" --abundance_file "$ABUNDANCE_FILE" \
    --model "$ISS_MODEL" --n_reads "$(iss_request "$microbe_total")" \
    --output "$WORKDIR/microbe" --cpus "$CPUS" --seed "$SEED" \
    > "$LOG_DIR/parallel_gen/rep${REP}_microbe.log" 2>&1

echo "  [2/2] host reads ($(iss_request "$host_total") requested)..."
"$ISS_BIN" generate \
    --genomes "$HUMAN_FASTA" \
    --model "$ISS_MODEL" --n_reads "$(iss_request "$host_total")" \
    --output "$WORKDIR/host" --cpus "$CPUS" --seed "$SEED" \
    > "$LOG_DIR/parallel_gen/rep${REP}_host.log" 2>&1

for f in "$WORKDIR/microbe_R1.fastq" "$WORKDIR/host_R1.fastq"; do
    [ -s "$f" ] || { echo "ERROR: ISS produced nothing at $f" >&2; exit 1; }
done

avail_microbe=$(( $(wc -l < "$WORKDIR/microbe_R1.fastq") / 4 ))
avail_host=$(( $(wc -l < "$WORKDIR/host_R1.fastq") / 4 ))
echo "  ISS produced $avail_microbe microbial and $avail_host host reads in R1"
[ "$avail_microbe" -ge "$microbe_total" ] || {
    echo "ERROR: need $microbe_total microbial reads, ISS gave $avail_microbe" >&2; exit 1; }
[ "$avail_host" -ge "$host_total" ] || {
    echo "ERROR: need $host_total host reads, ISS gave $avail_host" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Cut disjoint slices
# ---------------------------------------------------------------------------
# One pass per source, writing consecutive non-overlapping runs of records to
# the six per-sample files, so no read is used twice anywhere in the replicate.
slice_fastq() {
    local src="$1" prefix="$2" counts="$3"
    awk -v prefix="$prefix" -v counts="$counts" '
        BEGIN { n = split(counts, c, ","); k = 1; used = 0
                lim = c[1]; out = prefix k ".fastq" }
        NR % 4 == 1 {
            while (k <= n && used == lim) {
                close(out); k++
                if (k > n) exit
                lim = c[k]; used = 0; out = prefix k ".fastq"
            }
            used++
        }
        { print > out }
    ' "$src"
}

host_csv=$(IFS=,; echo "${HOST_N[*]}")
microbe_csv=$(IFS=,; echo "${MICROBE_N[*]}")
for i in $(seq 1 "${#HOST_PCTS[@]}"); do
    : > "$WORKDIR/hslice${i}.fastq"
    : > "$WORKDIR/mslice${i}.fastq"
done
slice_fastq "$WORKDIR/host_R1.fastq"    "$WORKDIR/hslice" "$host_csv"
slice_fastq "$WORKDIR/microbe_R1.fastq" "$WORKDIR/mslice" "$microbe_csv"

# ---------------------------------------------------------------------------
# Assemble, label, compress
# ---------------------------------------------------------------------------
MANIFEST="$MANIFEST_DIR/rep${REP}.tsv"
: > "$MANIFEST"

for i in $(seq 1 "${#HOST_PCTS[@]}"); do
    idx=$((i - 1))
    sid="${SAMPLE_IDS[$idx]}"
    pct="${HOST_PCTS[$idx]}"
    m="${MICROBE_N[$idx]}"
    h="${HOST_N[$idx]}"

    got_m=$(( $(wc -l < "$WORKDIR/mslice${i}.fastq") / 4 ))
    got_h=$(( $(wc -l < "$WORKDIR/hslice${i}.fastq") / 4 ))
    if [ "$got_m" -ne "$m" ] || [ "$got_h" -ne "$h" ]; then
        echo "ERROR: $sid sliced to ${got_m}+${got_h}, expected ${m}+${h}." >&2
        echo "       A sample at the wrong depth changes every runtime it appears in." >&2
        exit 1
    fi

    # Microbial records first, then host, matching the enhanced panel's layout.
    cat "$WORKDIR/mslice${i}.fastq" "$WORKDIR/hslice${i}.fastq" > "$WORKDIR/${sid}.fastq"

    # The ground-truth id is normalised exactly as the accuracy scripts
    # normalise a FASTQ header: first token, mate suffix removed. Storing the
    # whole header instead is what once made every accuracy table read as
    # precision 0, recall 0.
    {
        awk 'NR%4==1 {id=substr($1,2); sub(/\/.*$/,"",id); sub(/#.*$/,"",id); print id "\tmicrobe"}' \
            "$WORKDIR/mslice${i}.fastq"
        awk 'NR%4==1 {id=substr($1,2); sub(/\/.*$/,"",id); sub(/#.*$/,"",id); print id "\thost"}' \
            "$WORKDIR/hslice${i}.fastq"
    } | pigz -p "$CPUS" -c > "$LABEL_DIR/${sid}.labels.tsv.gz"

    pigz -p "$CPUS" -c "$WORKDIR/${sid}.fastq" > "$OUT_DIR/${sid}.fastq.gz"
    rm -f "$WORKDIR/${sid}.fastq" "$WORKDIR/mslice${i}.fastq" "$WORKDIR/hslice${i}.fastq"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sid" "$pct" "$REP" "$READS" "$h" "$m" >> "$MANIFEST"
    echo "  wrote $sid  (${pct}% host: ${h} host + ${m} microbial)"
done

# Read length is measured rather than asserted: it is set by the ISS error
# model, so a hardcoded value goes stale the moment the model changes.
first_read=$(zcat "$OUT_DIR/${SAMPLE_IDS[0]}.fastq.gz" | sed -n 2p)
cat > "$MANIFEST_DIR/rep${REP}.json" <<EOF
{
    "replicate": $((10#$REP)),
    "samples": ${#SAMPLE_IDS[@]},
    "reads_per_sample": $READS,
    "host_percentages": [$(IFS=,; echo "${HOST_PCTS[*]}")],
    "read_length": ${#first_read},
    "n_species": $N_SPECIES,
    "simulator": "InSilicoSeq",
    "model": "$ISS_MODEL",
    "seed": $SEED,
    "community_seed": "$SAMPLE_SEED"
}
EOF

echo "$STAMP" > "$DONE_FLAG"
echo "[rep $REP] done at $(date -Iseconds); ${#SAMPLE_IDS[@]} samples, ${#first_read} bp"
