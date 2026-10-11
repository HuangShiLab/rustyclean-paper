#!/usr/bin/env python3
"""Generate a mock/real-spike-in dataset with exact synthetic read IDs.

Manifest columns: class,label,path,abundance. `path` may contain two FASTQs as
comma-separated values. FASTA inputs are simulated; FASTQ inputs are sampled.
This tool does not claim a named published error model: metadata records the
simple uniform substitution model used for simulated FASTA reads.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import random
from pathlib import Path


def open_text(path: Path):
    return gzip.open(path, "rt") if path.suffix == ".gz" else path.open("rt")


def read_fasta(path: Path) -> list[str]:
    sequences: list[str] = []
    name = ""
    parts: list[str] = []
    with open_text(path) as handle:
        for line in handle:
            line = line.strip()
            if line.startswith(">"):
                if name:
                    sequences.append("".join(parts).upper())
                name, parts = line[1:].split()[0], []
            elif line:
                parts.append(line)
    if name:
        sequences.append("".join(parts).upper())
    if not sequences or any(not seq for seq in sequences):
        raise ValueError(f"empty or malformed FASTA: {path}")
    return sequences


def fastq_iter(path: Path):
    with open_text(path) as handle:
        while True:
            lines = [handle.readline() for _ in range(4)]
            if not lines[0]:
                return
            if len(lines) != 4 or not lines[0].startswith("@"):
                raise ValueError(f"malformed FASTQ in {path}")
            yield [line.rstrip("\n") for line in lines]


def sample_fastq(paths: list[Path], count: int, rng: random.Random) -> list[list[str]]:
    """Reservoir-sample complete records (or paired record pairs) from FASTQs."""
    if len(paths) not in {1, 2}:
        raise ValueError(f"FASTQ source needs one SE path or two PE paths: {paths}")
    if len(paths) == 2:
        sources = [fastq_iter(path) for path in paths]
        reservoir: list[list[str]] = []
        for index, pair in enumerate(zip(*sources)):
            if index < count:
                reservoir.append([pair[0][1], pair[0][3], pair[1][1], pair[1][3]])
            else:
                position = rng.randrange(index + 1)
                if position < count:
                    reservoir[position] = [pair[0][1], pair[0][3], pair[1][1], pair[1][3]]
        return reservoir
    reservoir = []
    for index, record in enumerate(fastq_iter(paths[0])):
        if index < count:
            reservoir.append([record[1], record[3]])
        else:
            position = rng.randrange(index + 1)
            if position < count:
                reservoir[position] = [record[1], record[3]]
    return reservoir


def reverse_complement(sequence: str) -> str:
    return sequence.translate(str.maketrans("ACGTN", "TGCAN"))[::-1]


def add_errors(sequence: str, rng: random.Random, rate: float) -> str:
    result = []
    for base in sequence:
        if rng.random() < rate:
            base = rng.choice([x for x in "ACGT" if x != base])
        result.append(base)
    return "".join(result)


def simulate_pair(contigs: list[str], rng: random.Random, length: int, rate: float):
    total = sum(map(len, contigs))
    point = rng.random() * total
    sequence = contigs[-1]
    for candidate in contigs:
        point -= len(candidate)
        if point <= 0:
            sequence = candidate
            break
    fragment_length = min(rng.randrange(200, 401), len(sequence))
    start = rng.randrange(0, len(sequence) - fragment_length + 1)
    fragment = sequence[start:start + fragment_length]
    if len(fragment) < length:
        fragment += "".join(rng.choice("ACGT") for _ in range(length - len(fragment)))
    if rng.random() < 0.5:
        fragment = reverse_complement(fragment)
    r1 = add_errors(fragment[:length], rng, rate)
    r2 = add_errors(reverse_complement(fragment[-length:]), rng, rate)
    return r1, "I" * length, r2, "I" * length


def write_record(handle, ident: str, sequence: str, quality: str, length: int) -> None:
    sequence = (sequence + "".join("ACGT" for _ in range(length)))[:length]
    quality = (quality + "I" * length)[:length]
    handle.write(f"@{ident}\n{sequence}\n+\n{quality}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--reads", type=int, default=1_000_000)
    parser.add_argument("--host-fraction", type=float, default=0.10)
    parser.add_argument("--read-length", type=int, default=150)
    parser.add_argument("--paired", action="store_true")
    parser.add_argument("--error-rate", type=float, default=0.005)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--compression-level", type=int, choices=range(1, 10), default=1)
    args = parser.parse_args()
    if not 0 < args.host_fraction < 1 or args.reads < 1:
        parser.error("requires 0<host-fraction<1 and reads>=1")
    rng = random.Random(args.seed)

    with args.manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        row["abundance"] = float(row.get("abundance") or 1)
    host_rows = [r for r in rows if r["class"] == "host"]
    microbe_rows = [r for r in rows if r["class"] == "microbe"]
    if len(host_rows) != 1 or not microbe_rows:
        raise ValueError("manifest requires exactly one host row and >=1 microbe row")

    labels = ["host" if rng.random() < args.host_fraction else "microbe" for _ in range(args.reads)]
    n_host = labels.count("host")
    host_row = host_rows[0]
    host_paths = [Path(x) for x in host_row["path"].split(",") if x]
    host_fastq_samples: list[list[str]] = []
    if all(path.suffix.lower().startswith(".fq") or ".fastq" in path.name or ".fq" in path.name for path in host_paths):
        if args.paired and len(host_paths) != 2:
            raise ValueError("paired host spike-in requires two FASTQ paths")
        host_fastq_samples = sample_fastq(host_paths, n_host, rng)
    host_contigs = [] if host_fastq_samples else read_fasta(host_paths[0])
    microbe_contigs: list[list[str]] = []
    for row in microbe_rows:
        path = Path(row["path"].split(",")[0])
        microbe_contigs.append(read_fasta(path))
    weights = [float(row["abundance"]) for row in microbe_rows]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    r1_path = args.output_dir / ("reads_R1.fastq.gz" if args.paired else "reads.fastq.gz")
    r2_path = args.output_dir / "reads_R2.fastq.gz" if args.paired else None
    with gzip.open(r1_path, "wt", compresslevel=args.compression_level) as out1, \
         (gzip.open(r2_path, "wt", compresslevel=args.compression_level) if r2_path else nullcontext()) as out2, \
         (args.output_dir / "ground_truth_labels.txt").open("w", encoding="utf-8") as truth:
        host_index = microbe_index = 0
        for index, label in enumerate(labels):
            ident = f"{label[0]}{args.seed}_{index:09d}"
            if label == "host":
                if host_fastq_samples:
                    sample = host_fastq_samples[host_index]
                    host_index += 1
                    r1, q1 = sample[0], sample[1]
                    if args.paired:
                        r2, q2 = sample[2], sample[3]
                    else:
                        r2 = q2 = ""
                else:
                    r1, q1, r2, q2 = simulate_pair(host_contigs, rng, args.read_length, args.error_rate)
            else:
                point = rng.random() * sum(weights)
                cumulative = 0.0
                selected = len(microbe_rows) - 1
                for row, weight, contigs in zip(microbe_rows, weights, microbe_contigs):
                    cumulative += weight
                    if point <= cumulative:
                        selected = microbe_rows.index(row)
                        break
                r1, q1, r2, q2 = simulate_pair(microbe_contigs[selected], rng, args.read_length, args.error_rate)
            write_record(out1, ident, r1, q1, args.read_length)
            if args.paired and out2 is not None:
                write_record(out2, ident, r2, q2, args.read_length)
            truth.write(f"{ident}\t{label}\n")

    metadata = {
        "manifest": str(args.manifest.resolve()), "reads": args.reads,
        "host_reads": n_host, "microbe_reads": args.reads - n_host,
        "host_fraction_observed": n_host / args.reads,
        "host_fraction_requested": args.host_fraction,
        "read_length": args.read_length, "paired": args.paired,
        "error_model": "uniform substitutions; rate only applied to simulated FASTA",
        "seed": args.seed,
        "host_source": str(host_paths[0].resolve()),
        "microbe_sources": [str(Path(r["path"].split(",")[0]).resolve()) for r in microbe_rows],
        "abundances": weights,
    }
    (args.output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    lines = []
    for path in sorted(args.output_dir.iterdir()):
        if path.is_file() and path.name != "manifest.sha256":
            lines.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}")
    (args.output_dir / "manifest.sha256").write_text("\n".join(lines) + "\n")
    print(json.dumps(metadata, sort_keys=True))


from contextlib import nullcontext  # noqa: E402


if __name__ == "__main__":
    main()
