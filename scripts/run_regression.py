#!/usr/bin/env python3
"""Regression runner for the Verilator build of the DMA UVM testbench.

Runs every test (parsed from tb/tests/dma_tests.svh) with N seeds, in
parallel, and writes:

  <out>/<test>_s<seed>/sim.log, coverage.dat   per run
  <out>/coverage_merged.dat                    merged Verilator coverage
  <out>/summary.md, summary.json               results + coverage

A run passes only if the simulator exits with status 0, the log contains
"** TEST PASSED **", the UVM report shows zero UVM_ERROR / UVM_FATAL and the
simulator printed no %Error line.
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import coverage_report  # noqa: E402


def discover_tests():
    src = (ROOT / "tb" / "tests" / "dma_tests.svh").read_text()
    return re.findall(r"^`DMA_TEST\((\w+)\s*,", src, re.M)


def judge(log: str, rc: int):
    reasons = []
    if rc != 0:
        reasons.append(f"exit status {rc}")
    if "** TEST PASSED **" not in log:
        reasons.append("no TEST PASSED banner")
    m = re.search(r"UVM_ERROR\s*:\s*(\d+)", log)
    if not m or int(m.group(1)) != 0:
        reasons.append(f"UVM_ERROR={m.group(1) if m else '?'}")
    m = re.search(r"UVM_FATAL\s*:\s*(\d+)", log)
    if not m or int(m.group(1)) != 0:
        reasons.append(f"UVM_FATAL={m.group(1) if m else '?'}")
    if re.search(r"^%Error", log, re.M):
        reasons.append("simulator %Error")
    return (len(reasons) == 0), reasons


def first_error(log: str) -> str:
    for line in log.splitlines():
        if re.match(r"^(UVM_ERROR|UVM_FATAL|%Error)", line) and " : " not in line[:12]:
            return line.strip()[:240]
    return ""


def run_one(binary: Path, test: str, seed: int, out: Path, timeout: int, extra):
    rdir = out / f"{test}_s{seed}"
    rdir.mkdir(parents=True, exist_ok=True)
    cmd = [str(binary), f"+UVM_TESTNAME={test}", f"+verilator+seed+{seed}",
           "+UVM_VERBOSITY=UVM_LOW", "+UVM_NO_RELNOTES",
           "+verilator+coverage+file+coverage.dat"] + extra
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=rdir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout, text=True, errors="replace")
        log, rc = p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        log = (e.stdout or "") if isinstance(e.stdout, str) else ""
        log += f"\n%Error: regression timeout after {timeout}s\n"
        rc = -1
    dt = time.time() - t0
    (rdir / "sim.log").write_text(log)
    ok, reasons = judge(log, rc)
    m = re.search(r"\$finish at ([\d.]+)\s*(\w+)", log)
    simtime = f"{m.group(1)} {m.group(2)}" if m else "?"
    return {"test": test, "seed": seed, "pass": ok, "reasons": reasons,
            "first_error": "" if ok else first_error(log), "wall_s": round(dt, 1),
            "sim_time": simtime, "dir": str(rdir.relative_to(out))}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bin", default=str(ROOT / "build" / "obj" / "Vtb_top"))
    ap.add_argument("--seeds", type=int, default=3, help="seeds per test")
    ap.add_argument("--seed-base", type=int, default=1)
    ap.add_argument("--tests", default="", help="comma separated subset")
    ap.add_argument("--out", default=str(ROOT / "build" / "regress"))
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--timeout", type=int, default=900, help="seconds per run")
    ap.add_argument("--plusargs", default="", help="extra plusargs for every run")
    args = ap.parse_args()

    binary = Path(args.bin).resolve()
    if not binary.exists():
        sys.exit(f"simulator binary {binary} not found - run 'make build' first")
    tests = [t for t in args.tests.split(",") if t] or discover_tests()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    extra = args.plusargs.split() if args.plusargs else []

    jobs = [(t, args.seed_base + i) for t in tests for i in range(args.seeds)]
    print(f"Running {len(jobs)} simulations ({len(tests)} tests x {args.seeds} seeds, {args.jobs} in parallel)")
    results = []
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_one, binary, t, s, out, args.timeout, extra): (t, s) for t, s in jobs}
        for f in cf.as_completed(futs):
            r = f.result()
            results.append(r)
            status = "PASS" if r["pass"] else "FAIL"
            print(f"  [{status}] {r['test']:<24} seed={r['seed']:<5} {r['wall_s']:>7.1f}s  sim={r['sim_time']}"
                  + ("" if r["pass"] else f"  <- {', '.join(r['reasons'])} | {r['first_error']}"), flush=True)
    wall = time.time() - t0
    results.sort(key=lambda r: (tests.index(r["test"]), r["seed"]))

    # Coverage
    dats = [str(out / r["dir"] / "coverage.dat") for r in results if (out / r["dir"] / "coverage.dat").exists()]
    cov = None
    if dats:
        merged = out / "coverage_merged.dat"
        subprocess.run(["verilator_coverage", "--write", str(merged)] + dats, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if merged.exists():
            cov = coverage_report.analyze(merged)
            (out / "coverage_report.md").write_text(coverage_report.to_markdown(cov))

    n_pass = sum(r["pass"] for r in results)
    lines = ["# Regression summary", "",
             f"- Simulations: {len(results)} ({len(tests)} tests x {args.seeds} seeds)",
             f"- Passed: {n_pass}/{len(results)}",
             f"- Wall time: {wall/60:.1f} min", ""]
    if cov:
        lines += coverage_report.summary_lines(cov) + [""]
    lines += ["| Test | Seeds | Pass | Sim time (last seed) |", "|---|---|---|---|"]
    for t in tests:
        rs = [r for r in results if r["test"] == t]
        lines.append(f"| {t} | {len(rs)} | {sum(r['pass'] for r in rs)}/{len(rs)} | {rs[-1]['sim_time'] if rs else '-'} |")
    fails = [r for r in results if not r["pass"]]
    if fails:
        lines += ["", "## Failures", ""]
        for r in fails:
            lines.append(f"- `{r['test']}` seed {r['seed']}: {', '.join(r['reasons'])} - `{r['first_error']}`")
    (out / "summary.md").write_text("\n".join(lines) + "\n")
    (out / "summary.json").write_text(json.dumps({"results": results, "coverage": cov}, indent=2))
    print("\n".join(lines))
    sys.exit(0 if n_pass == len(results) else 1)


if __name__ == "__main__":
    main()
