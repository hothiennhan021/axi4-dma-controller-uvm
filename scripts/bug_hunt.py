#!/usr/bin/env python3
"""Bug-injection campaign: prove the testbench catches realistic RTL bugs.

Every mutation below is a small, plausible design error. For each one the
script copies the sources to build/bugs/<id>/, applies the mutation, builds
the Verilator model, runs the regression subset and records which tests
failed and the first error message. A mutation that no test detects is a
testbench hole and makes the script exit with status 1.

Usage: bug_hunt.py [--bugs BUG-01,BUG-04] [--seeds 2] [--tests t1,t2]
Results: build/bugs/bug_hunt.md (and .json)
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (id, file, original text, mutated text, description)
MUTATIONS = [
    ("BUG-01", "rtl/dma_axi_engine.sv",
     "    if (d_dst_inc && (beats_c > {5'b0, dst_room})) beats_c = {5'b0, dst_room};\n",
     "",
     "Burst length ignores the destination 4 KB boundary (AW bursts may cross 4 KB)"),
    ("BUG-02", "rtl/dma_rr_arbiter.sv",
     "      idx = {1'b0, last_q} + (IW+1)'(i);",
     "      idx = (IW+1)'(i - 1);",
     "Arbiter degenerates to fixed priority (channel 0 always wins)"),
    ("BUG-03", "rtl/dma_channel.sv",
     "  assign fin_abort = busy & abort_pend & ~eng_sel;",
     "  assign fin_abort = busy & abort_pend;",
     "ABORT terminates the channel while its burst is still in flight"),
    ("BUG-04", "rtl/dma_top.sv",
     "    else        int_status <= (int_status & ~int_clr) | int_set;",
     "    else        int_status <= (|int_clr) ? int_set : (int_status | int_set);",
     "W1C to INT_STATUS clears every pending bit, not only the bits written as 1"),
    ("BUG-05", "rtl/dma_axi_engine.sv",
     "              if (rd_fail) begin\n                state <= S_IDLE;",
     "              if (1'b0) begin\n                state <= S_IDLE;",
     "Read error does not suppress the write burst (garbage written to the destination)"),
    ("BUG-06", "rtl/dma_axi_engine.sv",
     "            awburst_q <= d_dst_inc ? AXI_BURST_INCR : AXI_BURST_FIXED;",
     "            awburst_q <= AXI_BURST_INCR;",
     "AWBURST is always INCR, even for a fixed (FIFO) destination"),
    ("BUG-07", "rtl/dma_axi_engine.sv",
     "  assign m_axi_wlast   = (wcnt == len_q);",
     "  assign m_axi_wlast   = (wcnt == len_q) || (len_q > 4'd7 && wcnt == len_q - 4'd1);",
     "WLAST asserted one beat early on bursts longer than 8 beats"),
    ("BUG-08", "rtl/dma_top.sv",
     "    .allow     (glb_en & eng_idle),",
     "    .allow     (eng_idle),",
     "CTRL.EN is ignored by the arbiter (channels run while disabled)"),
    ("BUG-09", "rtl/dma_channel.sv",
     "  assign start_ok  = start_req & ~busy;",
     "  assign start_ok  = start_req & ~(busy & eng_sel);",
     "START while busy restarts the channel when no burst is in flight"),
    ("BUG-10", "rtl/dma_apb_regs.sv",
     "          CH_CFG, CH_SRC, CH_DST, CH_LEN, CH_CMD, CH_STAT: addr_ok = 1'b1;",
     "          CH_CFG, CH_SRC, CH_DST, CH_LEN, CH_CMD, CH_STAT, 5'h18: addr_ok = 1'b1;",
     "Channel offset 0x18 decoded as a register (no PSLVERR)"),
    ("BUG-11", "rtl/dma_axi_engine.sv",
     "            else             wcnt   <= wcnt + 4'd1;",
     "            else             wcnt   <= wcnt + 4'd1;\n          end else if (m_axi_wvalid && wcnt != len_q && wcnt[0]) begin\n            wcnt <= wcnt + 4'd1;",
     "Write data pointer advances without WREADY (data lost under back-pressure)"),
    ("BUG-12", "rtl/dma_channel.sv",
     "  assign last_ok   = busy & eng_done & ({11'b0, eng_beats} == rem);",
     "  assign last_ok   = busy & eng_done & ({11'b0, eng_beats} >= rem - 16'd1) & (rem != 16'd1 || eng_beats == 5'd1);",
     "Channel reports DONE one word early when the last burst is longer than one beat"),
    ("BUG-13", "rtl/dma_top.sv",
     "    else        int_status <= (int_status & ~int_clr) | int_set;",
     "    else        int_status <= (int_status | int_set) & ~int_clr;",
     "Software W1C wins over a hardware set in the same cycle (interrupt lost)"),
    ("BUG-14", "rtl/dma_axi_engine.sv",
     "    src_room = 11'd1024 - {1'b0, d_src[11:2]};",
     "    src_room = 11'd1023 - {1'b0, d_src[11:2]};",
     "Off-by-one in the source 4 KB room computation"),
]


def apply(src_root: Path, dst_root: Path, mut):
    bug_id, rel, old, new, _ = mut
    if dst_root.exists():
        shutil.rmtree(dst_root)
    for d in ("rtl", "tb", "sim", "scripts", "formal"):
        shutil.copytree(src_root / d, dst_root / d)
    shutil.copy(src_root / "Makefile", dst_root / "Makefile")
    f = dst_root / rel
    text = f.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"{bug_id}: original text not found exactly once in {rel}")
    f.write_text(text.replace(old, new))
    diff = subprocess.run(["diff", "-u", str(src_root / rel), str(f)], stdout=subprocess.PIPE, text=True).stdout
    return diff


def write_docs(results, out: Path):
    ddir = ROOT / "docs" / "bug_reports"
    ddir.mkdir(parents=True, exist_ok=True)
    for r in results:
        diff = (out / r["id"] / "mutation.diff").read_text() if (out / r["id"] / "mutation.diff").exists() else ""
        diff = re.sub(r"^(---|\+\+\+) \S*?/((rtl)/\S+).*$", r"\1 \2", diff, flags=re.M)
        body = [f"# {r['id']}: {r['desc']}", "",
                f"* File: `{r['file']}`",
                f"* Detected in simulation: {'yes' if r['detected'] else '**no**'}"
                + (f" - {r.get('n_failed', 0)}/{r.get('n_runs', 0)} runs failed" if r['detected'] else ""),
                f"* Failing tests: {', '.join('`' + t + '`' for t in r['failing_tests']) or '-'}",
                f"* Formal BMC (protocol properties): {'caught at `' + r['formal_where'] + '`' if r['formal'] else 'not caught (functional bug, outside the protocol property set)'}",
                "", "## Injected change", "", "```diff", diff.rstrip(), "```", "",
                "## First error reported", "", "```", r["first_error"] or "-", "```", ""]
        (ddir / f"{r['id']}.md").write_text("\n".join(body))
    (ROOT / "docs" / "bug_hunt_results.md").write_text((out / "bug_hunt.md").read_text())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bugs", default="")
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--tests", default="")
    ap.add_argument("--out", default=str(ROOT / "build" / "bugs"))
    ap.add_argument("--formal-only", action="store_true",
                    help="rerun only the formal check and merge into an existing bug_hunt.json")
    ap.add_argument("--docs", action="store_true", help="also write docs/bug_reports/ and docs/bug_hunt_results.md")
    ap.add_argument("--uvm-home", default=os.environ.get("UVM_HOME", str(ROOT / "third_party" / "uvm-core")))
    args = ap.parse_args()

    sel = [b for b in args.bugs.split(",") if b]
    muts = [m for m in MUTATIONS if not sel or m[0] in sel]
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    results = []
    prev = {}
    if args.formal_only and (out / "bug_hunt.json").exists():
        prev = {r["id"]: r for r in json.loads((out / "bug_hunt.json").read_text())}
    for m in muts:
        bug_id, rel, _, _, desc = m
        work = out / bug_id
        print(f"=== {bug_id}: {desc}", flush=True)
        diff = apply(ROOT, work / "src", m)
        (work / "mutation.diff").write_text(diff)
        # Formal (bounded proof of the protocol properties) - seconds per bug
        fdir = work / "src" / "formal"
        shutil.rmtree(fdir / "dma_bmc", ignore_errors=True)
        f = subprocess.run(["sby", "-f", "dma.sby", "bmc"], cwd=fdir, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
        formal_fail = "DONE (FAIL" in f.stdout
        m_line = re.search(r"failed assertion .* at (\S+)", f.stdout)
        formal_where = m_line.group(1) if m_line else ""
        print(f"    formal BMC: {'FAIL (bug caught)' if formal_fail else 'pass'} {formal_where}", flush=True)

        if args.formal_only:
            r = dict(prev.get(bug_id, {"id": bug_id, "desc": desc, "file": rel, "detected": False,
                                       "build_failed": False, "failing_tests": [], "first_error": ""}))
            r.update({"desc": desc, "formal": formal_fail, "formal_where": formal_where})
            results.append(r)
            continue

        bdir = work / "build"
        b = subprocess.run(["make", "-C", str(work / "src"), "build", f"BUILD_DIR={bdir}", "COV=0",
                            f"UVM_HOME={args.uvm_home}"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if b.returncode != 0 or not (bdir / "obj" / "Vtb_top").exists():
            print(b.stdout[-3000:])
            results.append({"id": bug_id, "desc": desc, "file": rel, "detected": False, "build_failed": True,
                            "failing_tests": [], "first_error": "build failed", "formal": formal_fail,
                            "formal_where": formal_where})
            continue
        cmd = [sys.executable, str(ROOT / "scripts" / "run_regression.py"), "--bin", str(bdir / "obj" / "Vtb_top"),
               "--seeds", str(args.seeds), "--out", str(work / "regress"), "--timeout", "600"]
        if args.tests:
            cmd += ["--tests", args.tests]
        subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        summ = json.loads((work / "regress" / "summary.json").read_text())
        fails = [r for r in summ["results"] if not r["pass"]]
        tests_failed = sorted({r["test"] for r in fails})
        first = fails[0]["first_error"] if fails else ""
        detected = len(fails) > 0
        print(f"    {'DETECTED' if detected else 'MISSED'} by {len(tests_failed)} test(s): {', '.join(tests_failed)}")
        if first:
            print(f"    first error: {first}")
        results.append({"id": bug_id, "desc": desc, "file": rel, "detected": detected, "build_failed": False,
                        "failing_tests": tests_failed, "n_runs": len(summ["results"]), "n_failed": len(fails),
                        "first_error": first, "formal": formal_fail, "formal_where": formal_where})
        shutil.rmtree(bdir / "obj", ignore_errors=True)   # keep disk usage down

    lines = ["# Bug-injection results", "",
             f"Simulation detected {sum(r['detected'] for r in results)}/{len(results)} injected bugs; "
             f"formal BMC (protocol properties only) detected {sum(r['formal'] for r in results)}/{len(results)}.", "",
             "| ID | Injected bug | Failing tests | Formal BMC | First simulation error |", "|---|---|---|---|---|"]
    for r in results:
        det = f"{len(r['failing_tests'])}: " + ", ".join(f"`{t}`" for t in r["failing_tests"]) if r["detected"] else "**MISSED**"
        err = r["first_error"].replace("|", "\\|")
        err = re.sub(r"\s+", " ", err)
        err = re.sub(r"^(UVM_\w+) \S+ @ \d+: \S+ ", r"\1 ", err)
        fm = "caught" if r["formal"] else "-"
        lines.append(f"| {r['id']} | {r['desc']} | {det} | {fm} | `{err[:150]}` |")
    (out / "bug_hunt.md").write_text("\n".join(lines) + "\n")
    (out / "bug_hunt.json").write_text(json.dumps(results, indent=2))
    if args.docs:
        write_docs(results, out)
    print("\n".join(lines))
    sys.exit(0 if all(r["detected"] for r in results) else 1)


if __name__ == "__main__":
    main()
