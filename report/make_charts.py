#!/usr/bin/env python3
"""Generate the report's SVG figures from the measured CSVs.

Geometry is computed rather than hand-placed so the marks land where the data
says. Colours come from the validated four-slot palette (blue / green / magenta
/ yellow); each series also carries a distinct marker shape, because the dark
palette's CVD separation sits at the FLOOR and is only admissible with a second
encoding channel.
"""
import csv
import collections
import pathlib
import math

SERIES = [
    # key,                    label,                  shape
    ("hostile_raw",            "Hostile",             "triangle"),
    ("rustyclean_auto_skipqc", "RustyClean --skip-qc", "square"),
    ("rustyclean_auto",        "RustyClean auto",     "circle"),
    ("kneaddata",              "KneadData",           "diamond"),
]
VAR = {"hostile_raw": "s3", "rustyclean_auto_skipqc": "s2",
       "rustyclean_auto": "s1", "kneaddata": "s4"}


def marker(shape, x, y, r, fill, extra=""):
    """A mark with a 2px surface ring, so overlapping points stay readable."""
    common = f'fill="{fill}" stroke="var(--chart-surface)" stroke-width="2" {extra}'
    if shape == "circle":
        return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" {common}/>'
    if shape == "square":
        s = r * 1.8
        return f'<rect x="{x-s/2:.1f}" y="{y-s/2:.1f}" width="{s:.1f}" height="{s:.1f}" rx="1.5" {common}/>'
    if shape == "triangle":
        h = r * 2.1
        pts = f"{x:.1f},{y-h*0.6:.1f} {x-h*0.55:.1f},{y+h*0.42:.1f} {x+h*0.55:.1f},{y+h*0.42:.1f}"
        return f'<polygon points="{pts}" {common}/>'
    s = r * 1.35
    pts = f"{x:.1f},{y-s:.1f} {x+s:.1f},{y:.1f} {x:.1f},{y+s:.1f} {x-s:.1f},{y:.1f}"
    return f'<polygon points="{pts}" {common}/>'


def load_tradeoff(path):
    rows = list(csv.DictReader(open(path)))
    by = collections.defaultdict(dict)
    for r in rows:
        by[r["dataset"]][r["tool"]] = r
    order = sorted(by, key=lambda d: int(d.split("M_")[0]))
    data = {}
    for key, _, _ in SERIES:
        pts = []
        for ds in order:
            r = by[ds][key]
            fp, tn, fn, tp = (int(r[k]) for k in ("fp", "tn", "fn", "tp"))
            pts.append((100 * fp / (fp + tn), 100 * fn / (fn + tp), ds))
        data[key] = pts
    return data, order


def chart_tradeoff(data):
    W, H = 720, 430
    L, R, T, B = 62, 176, 26, 52
    pw, ph = W - L - R, H - T - B
    xmax, ymax = 3.0, 1.05
    fx = lambda v: L + v / xmax * pw
    fy = lambda v: T + ph - v / ymax * ph

    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="宿主残留与微生物误删的取舍">']
    s.append('<title>四个工具在两类错误上的取舍</title>')

    # grid, recessive
    for gx in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
        s.append(f'<line x1="{fx(gx):.1f}" y1="{T}" x2="{fx(gx):.1f}" y2="{T+ph}" '
                 f'stroke="var(--chart-grid)" stroke-width="1"/>')
        s.append(f'<text x="{fx(gx):.1f}" y="{T+ph+18}" text-anchor="middle" '
                 f'class="tick">{gx:g}%</text>')
    for gy in [0.2, 0.4, 0.6, 0.8, 1.0]:
        s.append(f'<line x1="{L}" y1="{fy(gy):.1f}" x2="{L+pw}" y2="{fy(gy):.1f}" '
                 f'stroke="var(--chart-grid)" stroke-width="1"/>')
        s.append(f'<text x="{L-9}" y="{fy(gy)+4:.1f}" text-anchor="end" class="tick">{gy:g}%</text>')
    s.append(f'<line x1="{L}" y1="{T}" x2="{L}" y2="{T+ph}" stroke="var(--chart-axis)" stroke-width="1"/>')
    s.append(f'<line x1="{L}" y1="{T+ph}" x2="{L+pw}" y2="{T+ph}" stroke="var(--chart-axis)" stroke-width="1"/>')

    s.append(f'<text x="{L+pw/2:.0f}" y="{H-12}" text-anchor="middle" class="axis-label">'
             f'宿主残留 — 未清除的宿主读占比 →</text>')
    s.append(f'<text x="16" y="{T+ph/2:.0f}" text-anchor="middle" class="axis-label" '
             f'transform="rotate(-90 16 {T+ph/2:.0f})">微生物误删 — 被删的微生物读占比 →</text>')

    # "better" corner
    s.append(f'<text x="{L+10}" y="{T+ph-10}" class="annot">← 两类错误都更小</text>')

    # Anchor each label beside the series' rightmost point, then push the labels
    # apart vertically: at the centroid, "Hostile" and "RustyClean --skip-qc"
    # landed 2px apart in y and overlapped horizontally.
    anchors = []
    for key, label, shape in SERIES:
        pts = data[key]
        col = f"var(--{VAR[key]})"
        path = " ".join(("M" if i == 0 else "L") + f"{fx(p[0]):.1f},{fy(p[1]):.1f}"
                        for i, p in enumerate(pts))
        s.append(f'<path d="{path}" fill="none" stroke="{col}" stroke-width="2" '
                 f'stroke-opacity="0.42" stroke-linejoin="round"/>')
        for x, y, ds in pts:
            s.append(f'<g><title>{label} · {ds}\n宿主残留 {x:.2f}% · 微生物误删 {y:.3f}%</title>'
                     + marker(shape, fx(x), fy(y), 5.5, col) + '</g>')
        rx, ry, _ = max(pts, key=lambda p: p[0])
        anchors.append([label, fx(rx) + 14, fy(ry) + 4, col])

    MIN_GAP = 17
    anchors.sort(key=lambda a: a[2])
    for i in range(1, len(anchors)):
        if anchors[i][2] - anchors[i - 1][2] < MIN_GAP:
            anchors[i][2] = anchors[i - 1][2] + MIN_GAP
    # Clamping each label to the plot bottom would undo the spacing just applied
    # -- two series whose rightmost points both sit on the zero line ended up on
    # the same y again. Shift the whole set up by however much it overflows.
    overflow = anchors[-1][2] - (T + ph)
    if overflow > 0:
        for a in anchors:
            a[2] -= overflow
    for label, lx, ly, col in anchors:
        s.append(f'<text x="{lx:.1f}" y="{ly:.1f}" class="series-label">{label}</text>')

    s.append('</svg>')
    return "\n".join(s)


def chart_speedup(pairs):
    """pairs: list of (host_pct, kneaddata_ratio, hostile_ratio, depth_label)"""
    W, H = 720, 300
    L, R, T, B = 58, 150, 22, 50
    pw, ph = W - L - R, H - T - B
    ymax = 9.0
    fx = lambda v: L + (v / 100) * pw
    fy = lambda v: T + ph - (v / ymax) * ph

    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="相对两个对照工具的加速比">']
    s.append('<title>加速比随宿主比例的变化</title>')
    for gy in [1, 3, 5, 7, 9]:
        s.append(f'<line x1="{L}" y1="{fy(gy):.1f}" x2="{L+pw}" y2="{fy(gy):.1f}" '
                 f'stroke="var(--chart-grid)" stroke-width="1"/>')
        s.append(f'<text x="{L-9}" y="{fy(gy)+4:.1f}" text-anchor="end" class="tick">{gy}×</text>')
    s.append(f'<line x1="{L}" y1="{fy(1):.1f}" x2="{L+pw}" y2="{fy(1):.1f}" '
             f'stroke="var(--chart-axis)" stroke-width="1.5" stroke-dasharray="4 3"/>')
    s.append(f'<text x="{L+pw-4}" y="{fy(1)-7:.1f}" text-anchor="end" class="annot">1× 持平</text>')
    for hp in [0, 25, 50, 75, 100]:
        s.append(f'<text x="{fx(hp):.1f}" y="{T+ph+18}" text-anchor="middle" class="tick">{hp}%</text>')
    s.append(f'<line x1="{L}" y1="{T+ph}" x2="{L+pw}" y2="{T+ph}" stroke="var(--chart-axis)" stroke-width="1"/>')
    s.append(f'<text x="{L+pw/2:.0f}" y="{H-11}" text-anchor="middle" class="axis-label">数据集的宿主比例 →</text>')

    for idx, (col_var, label, shape) in enumerate(
            [("s4", "对 KneadData", "diamond"), ("s3", "对 Hostile", "triangle")]):
        col = f"var(--{col_var})"
        pts = [(hp, kd if idx == 0 else ho, dep) for hp, kd, ho, dep in pairs]
        path = " ".join(("M" if i == 0 else "L") + f"{fx(p[0]):.1f},{fy(p[1]):.1f}"
                        for i, p in enumerate(pts))
        s.append(f'<path d="{path}" fill="none" stroke="{col}" stroke-width="2" '
                 f'stroke-opacity="0.5" stroke-linejoin="round"/>')
        for hp, v, dep in pts:
            s.append(f'<g><title>{label} · 宿主 {hp}% · 深度 {dep} · {v:.2f}×</title>'
                     + marker(shape, fx(hp), fy(v), 5, col) + '</g>')
        lx, ly, _ = pts[-1]
        s.append(f'<text x="{fx(lx)+13:.1f}" y="{fy(ly)+4:.1f}" class="series-label">{label}</text>')
    s.append('</svg>')
    return "\n".join(s)


def chart_memory(items):
    """items: list of (label, gb, is_rustyclean)"""
    W = 720
    rowh, gap = 30, 8
    L, T, R = 168, 18, 74
    H = T + len(items) * (rowh + gap) + 34
    pw = W - L - R
    vmax = 16.0
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="各工具峰值内存">']
    s.append('<title>峰值内存</title>')
    for gx in [0, 4, 8, 12, 16]:
        x = L + gx / vmax * pw
        s.append(f'<line x1="{x:.1f}" y1="{T}" x2="{x:.1f}" y2="{T+len(items)*(rowh+gap)-gap:.0f}" '
                 f'stroke="var(--chart-grid)" stroke-width="1"/>')
        s.append(f'<text x="{x:.1f}" y="{H-10}" text-anchor="middle" class="tick">{gx} GB</text>')
    for i, (label, gb, hero) in enumerate(items):
        y = T + i * (rowh + gap)
        w = max(2, gb / vmax * pw)
        col = "var(--s1)" if hero else "var(--chart-bar-muted)"
        s.append(f'<text x="{L-12}" y="{y+rowh/2+4:.0f}" text-anchor="end" class="bar-label">{label}</text>')
        s.append(f'<g><title>{label} · 峰值 {gb:.1f} GB</title>'
                 f'<rect x="{L}" y="{y}" width="{w:.1f}" height="{rowh}" rx="4" fill="{col}"/></g>')
        s.append(f'<text x="{L+w+9:.1f}" y="{y+rowh/2+4:.0f}" class="bar-value">{gb:.1f}</text>')
    s.append('</svg>')
    return "\n".join(s)


if __name__ == "__main__":
    import sys
    base = sys.argv[1] if len(sys.argv) > 1 else "."
    data, order = load_tradeoff(f"{base}/scratch/accuracy_comparison.csv")

    # All eight datasets. Two sit at 90% host (30M and 60M) and they differ --
    # 5.78x and 6.60x -- so collapsing them to one point would hide the effect of
    # depth and quietly discard a measurement.
    speed = [(1, 0.99, 0.54, "5M"), (5, 1.09, 0.68, "5M"), (10, 1.72, 0.91, "10M"),
             (50, 4.42, 1.32, "30M"), (70, 3.27, 1.14, "30M"), (90, 5.78, 0.62, "30M"),
             (90, 6.60, 0.99, "60M"), (99, 8.60, 1.08, "60M")]

    mem = [("RustyClean k2 混合库", 15.6, True), ("minimap2 后端", 13.4, False),
           ("RustyClean + recheck", 12.7, True), ("RustyClean k2 基线", 12.3, True),
           ("RustyClean auto", 6.7, True), ("Hostile", 3.5, False), ("KneadData", 1.1, False)]

    out = {"tradeoff": chart_tradeoff(data), "speedup": chart_speedup(speed),
           "memory": chart_memory(mem)}
    out_dir = pathlib.Path(__file__).resolve().parent
    for k, v in out.items():
        dest = out_dir / f"chart_{k}.svg"
        dest.write_text(v)
        print(f"  {k}: {len(v)} bytes -> {dest}")
