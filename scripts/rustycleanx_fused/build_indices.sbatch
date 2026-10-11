#!/bin/bash
#SBATCH --job-name=rcx_build_idx
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=160G
#SBATCH --time=24:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_build_indices-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_build_indices-%j.err

set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
OUT=$REPO/runs/rustycleanx_fused/indices
HOST_FASTA=/lustre1/g/aos_shihuang/databases/kraken2/kraken16/genomes/GCF_000001405.40_GRCh38.p14_genomic.fna.gz
GTDB=/lustre1/g/aos_shihuang/databases/GTDB/GTDBr202/GTDBr202_reference_genome
LIST=$OUT/microbe_fasta_list.txt

mkdir -p "$OUT"
find "$GTDB" -maxdepth 1 -type f -name '*.fna' | sort | sed -n '1,100p' > "$LIST"
MAPFILE_LIST=$(tr '\n' '\0' < "$LIST")
ARGS=()
while IFS= read -r -d '' fasta; do
  ARGS+=(--microbe-fasta "$fasta")
done < <(tr '\n' '\0' < "$LIST")

"$REPO/rustyclean-x/target/release/build_indices" \
  --host-fasta "$HOST_FASTA" \
  "${ARGS[@]}" \
  --outdir "$OUT" \
  --max-minimizer 20000000 \
  --max-gapped 50000000 \
  --max-microbial 200000000
