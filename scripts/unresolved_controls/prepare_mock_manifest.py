#!/usr/bin/env python3
"""Prepare a reproducible manifest and divergent-host FASTA for mock truth.

The host sequence is the longest sequence in a supplied multi-FASTA, with a
seeded fraction of bases substituted. This creates a transparent synthetic
divergence challenge; it is not an authentic unindexed human population genome.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import random
from pathlib import Path


def open_fasta(path: Path):
    return gzip.open(path, "rt") if path.suffix == ".gz" else path.open("rt")


def fasta_sequences(path: Path):
    name = None
    parts: list[str] = []
    with open_fasta(path) as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith(">"):
                if name is not None:
                    yield name, "".join(parts)
                name, parts = line[1:].split()[0], []
            elif line:
                parts.append(line)
    if name is not None:
        yield name, "".join(parts)


def choose_genomes(directory: Path, count: int, seed: int) -> list[Path]:
    extensions = {".fna", ".fasta", ".fa", ".fna.gz", ".fasta.gz", ".fa.gz"}
    candidates = [p for p in directory.iterdir()
                  if p.is_file() and p.suffix in extensions or p.name.endswith(tuple(extensions))]
    candidates = list(dict.fromkeys(candidates))
    if len(candidates) < count:
        raise ValueError(f"only {len(candidates)} genomes in {directory}")
    ranked = sorted(candidates, key=lambda p: hashlib.sha256((f"{seed}:{p.name}").encode()).digest())
    return ranked[:count]


def write_mutated_host(source: Path, output: Path, rate: float, seed: int) -> dict:
    best_name, best_length = None, -1
    for name, sequence in fasta_sequences(source):
        if len(sequence) > best_length:
            best_name, best_length = name, len(sequence)
    if best_name is None or best_length < 10000:
        raise ValueError(f"no large sequence in {source}")
    rng = random.Random(seed)
    alphabet = "ACGT"
    written = 0
    with open_fasta(source) as inp, output.open("wt") as out:
        current = False
        for raw in inp:
            if raw.startswith(">"):
                current = raw[1:].split()[0] == best_name
                if current:
                    out.write(f">synthetic_divergent_host__{best_name}__substitution_rate_{rate}\n")
                continue
            if not current:
                continue
            sequence = "".join(raw.split())
            changed = []
            for base in sequence.upper():
                if base in alphabet and rng.random() < rate:
                    base = rng.choice([x for x in alphabet if x != base])
                changed.append(base)
            fragment = "".join(changed)
            for start in range(0, len(fragment), 60):
                line = fragment[start:start + 60]
                out.write(line + "\n")
                written += len(line)
    return {"selected_header": best_name, "input_length": best_length, "written_bp": written}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--human-fasta", required=True, type=Path)
    parser.add_argument("--microbe-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--species", type=int, default=5)
    parser.add_argument("--mutation-rate", type=float, default=0.01)
    parser.add_argument("--seed", type=int, default=918273)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    host_path = args.output_dir / "synthetic_divergent_host.fna"
    host_info = write_mutated_host(args.human_fasta, host_path, args.mutation_rate, args.seed)
    genomes = choose_genomes(args.microbe_dir, args.species, args.seed)
    manifest = args.output_dir / "mock_manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="") as handle:
        handle.write("class,label,path,abundance\n")
        handle.write(f"host,synthetic_divergent_host,{host_path.resolve()},1\n")
        for index, genome in enumerate(genomes, 1):
            handle.write(f"microbe,mock_species_{index:02d},{genome.resolve()},1\n")
    metadata = {
        "human_source": str(args.human_fasta.resolve()),
        "microbe_directory": str(args.microbe_dir.resolve()),
        "microbe_genomes": [str(p.resolve()) for p in genomes],
        "host_mutation_model": f"seeded uniform substitutions, rate={args.mutation_rate}",
        "seed": args.seed,
        **host_info,
    }
    (args.output_dir / "prepare_metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
