#!/usr/bin/env python3
"""Refresh the generated sections of README.md from build results.

  RESULTS : build/regress/summary.json (+ formal / synthesis logs if present)
  BUGS    : build/bugs/bug_hunt.md
Only the text between the <!-- X:BEGIN --> / <!-- X:END --> markers changes.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def replace(text, tag, body):
    pat = re.compile(rf"(<!-- {tag}:BEGIN -->\n).*?(<!-- {tag}:END -->)", re.S)
    return pat.sub(lambda m: m.group(1) + body.rstrip() + "\n" + m.group(2), text)


def results_table():
    summ = json.loads((ROOT / "build" / "regress" / "summary.json").read_text())
    res, cov = summ["results"], summ["coverage"]
    tests = sorted({r["test"] for r in res})
    seeds = len(res) // max(len(tests), 1)
    n_pass = sum(r["pass"] for r in res)
    n_items = sum(len(v["items"]) for v in cov["covergroups"].values())
    n_bins = sum(i["total"] for v in cov["covergroups"].values() for i in v["items"].values())
    cp = cov["cover_properties"]
    rows = [
        ("Tests", f"{len(tests)}"),
        ("Regression", f"{len(res)} runs ({len(tests)} tests x {seeds} seeds), **{n_pass}/{len(res)} pass**"),
        ("Functional coverage", f"**{cov['functional_pct']:.1f}%** ({len(cov['covergroups'])} covergroups, "
                                f"{n_items} coverpoints/crosses, {n_bins} bins)"),
        ("SVA cover properties", f"{sum(1 for c in cp.values() if c > 0)}/{len(cp)} hit"),
        ("RTL line coverage", f"**{cov['code']['line']['pct']:.1f}%** ({cov['code']['line']['hit']}/{cov['code']['line']['total']})"),
        ("RTL toggle coverage", f"{cov['code']['toggle']['pct']:.1f}% - the untoggled bits are structurally constant "
                                "(reserved register bits, unused upper INT/BUSY bits, AxLEN[7:4], AxSIZE, WSTRB, upper ID bits)"),
        ("Scoreboard checks", "every APB read, every AXI burst and data beat, every grant, the irq pin on every cycle"),
    ]
    extra = ROOT / "build" / "results_extra.json"
    if extra.exists():
        for k, v in json.loads(extra.read_text()).items():
            rows.append((k, v))
    out = ["| Metric | Value |", "|---|---|"] + [f"| {k} | {v} |" for k, v in rows]
    return "\n".join(out)


def main():
    readme = ROOT / "README.md"
    text = readme.read_text()
    if (ROOT / "build" / "regress" / "summary.json").exists():
        text = replace(text, "RESULTS", results_table())
    bugs = ROOT / "build" / "bugs" / "bug_hunt.md"
    if bugs.exists():
        body = bugs.read_text().split("\n", 2)[2]     # drop the '# ...' title
        rows = []
        for line in body.splitlines():
            cells = line.split(" | ")
            # compact the "Failing tests" column: "N: `a`, `b`, ..." -> "N tests"
            if line.startswith("| BUG-") and len(cells) >= 5:
                m = re.match(r"(\d+): (.*)", cells[2])
                if m:
                    tests = re.findall(r"`(\w+)`", m.group(2))
                    shown = ", ".join(f"`{t}`" for t in tests[:2])
                    cells[2] = f"{m.group(1)} ({shown}{', ...' if len(tests) > 2 else ''})"
                cells[1] = f"[{cells[1]}](docs/bug_reports/{cells[0].strip('| ')}.md)"
                line = " | ".join(cells)
            rows.append(line)
        body = "\n".join(rows) + "\n\nFull table: [`docs/bug_hunt_results.md`](docs/bug_hunt_results.md)."
        text = replace(text, "BUGS", body)
    readme.write_text(text)
    print("README.md updated")


if __name__ == "__main__":
    main()
