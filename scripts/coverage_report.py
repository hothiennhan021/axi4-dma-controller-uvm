#!/usr/bin/env python3
"""Summarise a (merged) Verilator coverage.dat file.

* Functional coverage: covergroup bins and SVA cover properties
  (Verilator 'user' coverage). Covergroup coverage is computed per
  coverpoint / cross as hit bins / total bins, then averaged per covergroup
  the same way get_coverage() does (equal weights).
* Code coverage: line and toggle points of the RTL (files under rtl/).

Usage: coverage_report.py coverage_merged.dat [--md out.md]
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

REC = re.compile(r"^C '(.*)' (\d+)\s*$")


def parse(path: Path):
    points = []
    for line in path.read_text(errors="replace").splitlines():
        m = REC.match(line)
        if not m:
            continue
        body, count = m.group(1), int(m.group(2))
        fields = {}
        for kv in body.split("\x01"):
            if not kv:
                continue
            k, _, v = kv.partition("\x02")
            fields[k] = v
        fields["count"] = count
        points.append(fields)
    return points


def analyze(path):
    pts = parse(Path(path))
    res = {"covergroups": {}, "cover_properties": {}, "code": {}}

    # ---- covergroups -------------------------------------------------------
    # Verilator records: t=covergroup, page="v_covergroup/<type name>",
    # h="<type name>.<coverpoint or cross>.<bin>", bin_type=ignore|illegal
    # for bins that do not count.
    groups = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    holes = defaultdict(list)
    for p in pts:
        if p.get("t") != "covergroup":
            continue
        if p.get("bin_type", "") in ("ignore", "illegal"):
            continue
        cg = p.get("page", "").split("/", 1)[-1].replace("__vlAnonCG_", "")
        parts = p.get("h", "").split(".", 2)
        cp = parts[1] if len(parts) > 2 else p.get("bin", "?")
        groups[cg][cp][1] += 1
        if p["count"] > 0:
            groups[cg][cp][0] += 1
        else:
            holes[cg].append(".".join(parts[1:]))
    for cg, cps in sorted(groups.items()):
        items = {cp: {"hit": h, "total": t, "pct": 100.0 * h / t if t else 100.0} for cp, (h, t) in sorted(cps.items())}
        pct = sum(v["pct"] for v in items.values()) / len(items) if items else 0.0
        res["covergroups"][cg] = {"pct": pct, "items": items, "holes": sorted(holes[cg])}

    # ---- cover properties -----------------------------------------------------
    for p in pts:
        if p.get("t") == "user" and p.get("page", "").startswith("v_user"):
            res["cover_properties"][p.get("h", p.get("o", "?"))] = p["count"]

    # ---- code coverage (RTL only) -----------------------------------------------
    code = defaultdict(lambda: [0, 0])
    for p in pts:
        f = p.get("f", "")
        page = p.get("page", "")
        if "rtl/" not in f:
            continue
        if page.startswith("v_line") or page.startswith("v_branch"):
            kind = "line"
        elif page.startswith("v_toggle"):
            kind = "toggle"
        else:
            continue
        code[kind][1] += 1
        if p["count"] > 0:
            code[kind][0] += 1
    for k, (h, t) in code.items():
        res["code"][k] = {"hit": h, "total": t, "pct": 100.0 * h / t if t else 100.0}

    if res["covergroups"]:
        res["functional_pct"] = sum(v["pct"] for v in res["covergroups"].values()) / len(res["covergroups"])
    return res


def summary_lines(res):
    out = []
    if "functional_pct" in res:
        out.append(f"- Functional coverage (covergroups, average): {res['functional_pct']:.1f}%")
        for cg, v in res["covergroups"].items():
            out.append(f"  - {cg}: {v['pct']:.1f}%")
    if res["cover_properties"]:
        hit = sum(1 for c in res["cover_properties"].values() if c > 0)
        out.append(f"- SVA cover properties hit: {hit}/{len(res['cover_properties'])}")
    for k in ("line", "toggle"):
        if k in res["code"]:
            v = res["code"][k]
            out.append(f"- RTL {k} coverage: {v['pct']:.1f}% ({v['hit']}/{v['total']})")
    return out


def to_markdown(res):
    lines = ["# Coverage report", ""] + summary_lines(res) + [""]
    for cg, v in res["covergroups"].items():
        lines += [f"## {cg} ({v['pct']:.1f}%)", "", "| Coverpoint / cross | Bins hit | Total | % |", "|---|---|---|---|"]
        for cp, it in v["items"].items():
            lines.append(f"| {cp} | {it['hit']} | {it['total']} | {it['pct']:.1f} |")
        if v.get("holes"):
            lines += ["", "Uncovered bins: " + ", ".join(f"`{h}`" for h in v["holes"])]
        lines.append("")
    if res["cover_properties"]:
        lines += ["## SVA cover properties", "", "| Property | Hits |", "|---|---|"]
        for n, c in sorted(res["cover_properties"].items()):
            lines.append(f"| {n} | {c} |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("dat")
    ap.add_argument("--md")
    a = ap.parse_args()
    r = analyze(a.dat)
    print("\n".join(summary_lines(r)))
    if a.md:
        Path(a.md).write_text(to_markdown(r))
