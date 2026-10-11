#!/usr/bin/env python3
"""Compare retained read-ID sets between two FASTQ files."""

import gzip
import sys


def read_ids(path: str) -> set[str]:
    opener = gzip.open if path.endswith(".gz") else open
    ids = set()
    with opener(path, "rt", encoding="utf-8", errors="ignore") as handle:
        for index, line in enumerate(handle):
            if index % 4:
                continue
            ids.add(line.split()[0][1:].split("/")[0].split("#")[0])
    return ids


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: compare_fastq_id_sets.py OLD.fastq.gz NEW.fastq.gz")
    old_ids = read_ids(sys.argv[1])
    new_ids = read_ids(sys.argv[2])
    only_old = old_ids - new_ids
    only_new = new_ids - old_ids
    union = old_ids | new_ids
    print(f"old_ids={len(old_ids)}")
    print(f"new_ids={len(new_ids)}")
    print(f"shared_ids={len(old_ids & new_ids)}")
    print(f"only_old={len(only_old)}")
    print(f"only_new={len(only_new)}")
    print(f"jaccard={len(old_ids & new_ids) / len(union):.8f}" if union else "jaccard=nan")
    for read_id in list(only_old)[:10]:
        print(f"ONLY_OLD\t{read_id}")
    for read_id in list(only_new)[:10]:
        print(f"ONLY_NEW\t{read_id}")


if __name__ == "__main__":
    main()
