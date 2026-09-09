#!/usr/bin/env python3
"""Replace the report's inline SVG figures with freshly generated ones.

Each figure is matched by its aria-label rather than by position, so adding or
reordering sections in the report does not silently swap two charts.
"""
import pathlib
import re
import sys

ARIA_TO_CHART = {
    "宿主残留与微生物误删的取舍": "tradeoff",
    "相对两个对照工具的加速比": "speedup",
    "各工具峰值内存": "memory",
    "并行吞吐量随并发数的变化": "scaling",
    "峰值并发内存随并发数的变化": "scaling_memory",
}


def main():
    here = pathlib.Path(__file__).resolve().parent
    html = here / "rustyclean-status.html"
    src = html.read_text()

    charts = {}
    for name in set(ARIA_TO_CHART.values()):
        p = here / f"chart_{name}.svg"
        if p.exists():
            charts[name] = p.read_text()
        elif name.startswith("scaling"):
            # A separate experiment with its own run tree; it may not exist yet.
            print(f"  no {p.name} yet; leaving that figure as it stands")
        else:
            sys.exit(f"ERROR: missing {p}. Run make_charts.py first.")

    replaced = []

    def swap(m):
        block = m.group(0)
        for aria, name in ARIA_TO_CHART.items():
            if f'aria-label="{aria}"' in block and name in charts:
                replaced.append(name)
                return charts[name]
        return block

    out, _ = re.subn(r"<svg.*?</svg>", swap, src, flags=re.S)

    missing = set(charts) - set(replaced)
    if missing:
        sys.exit(f"ERROR: these figures were not found in the report: {sorted(missing)}")

    html.write_text(out)
    print(f"  embedded {len(replaced)} figures: {', '.join(replaced)}")


if __name__ == "__main__":
    main()
