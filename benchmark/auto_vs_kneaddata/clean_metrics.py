#!/usr/bin/env python3
"""Strip ANSI escape codes from the RustyClean metrics CSV."""

import re
import sys


def clean(s: str) -> str:
    # Remove ANSI colour/style escape sequences.
    ansi = re.compile(r"\x1b\[[0-9;]*m")
    return ansi.sub("", s)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.csv> <output.csv>", file=sys.stderr)
        sys.exit(1)

    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "r", encoding="utf-8") as fin, \
         open(out_path, "w", encoding="utf-8") as fout:
        for line in fin:
            fout.write(clean(line))


if __name__ == "__main__":
    main()
