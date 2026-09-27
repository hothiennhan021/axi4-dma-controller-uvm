#!/usr/bin/env python3
"""Vivado XSim flow (Windows Git Bash / Linux). Needs xvlog/xelab/xsim on PATH.

    python sim/xsim/run_xsim.py --test dma_smoke_test --seed 1
    python sim/xsim/run_xsim.py --regress --seeds 3

Compiles once (UVM 1.2 shipped with Vivado, -L uvm), then runs each
test/seed in build/xsim/<test>_s<seed>/. A run passes when the log contains
"** TEST PASSED **" and zero UVM_ERROR/UVM_FATAL.

NOTE: the CI flow is Verilator (see Makefile); this script is provided for
Vivado users and is not exercised by CI.
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "xsim"


def tool(name):
    exe = shutil.which(name) or shutil.which(name + ".bat")
    if not exe:
        sys.exit(f"{name} not found on PATH (source Vivado settings64.sh / settings64.bat)")
    return exe


def read_filelist():
    incs, srcs = [], []
    for line in (ROOT / "sim" / "filelist.f").read_text().splitlines():
        line = line.split("//", 1)[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            incs.append(str(ROOT / line[len("+incdir+"):]))
        else:
            srcs.append(str(ROOT / line))
    return incs, srcs


def compile_all():
    BUILD.mkdir(parents=True, exist_ok=True)
    incs, srcs = read_filelist()
    cmd = [tool("xvlog"), "-sv", "-L", "uvm", "--define", "UVM_HDL_NO_DPI"]
    for i in incs:
        cmd += ["-i", i]
    cmd += srcs
    subprocess.run(cmd, cwd=BUILD, check=True)
    subprocess.run([tool("xelab"), "tb_top", "-L", "uvm", "-timescale", "1ns/1ps",
                    "-s", "tb_top_snap", "--debug", "off"], cwd=BUILD, check=True)


def run(test, seed):
    rdir = BUILD / f"{test}_s{seed}"
    rdir.mkdir(parents=True, exist_ok=True)
    log = rdir / "sim.log"
    subprocess.run([tool("xsim"), "tb_top_snap", "-R", "--xsimdir", str(BUILD / "xsim.dir"),
                    "-testplusarg", f"UVM_TESTNAME={test}", "-testplusarg", "UVM_NO_RELNOTES",
                    "-sv_seed", str(seed), "-log", str(log)], cwd=BUILD)
    text = log.read_text(errors="replace") if log.exists() else ""
    ok = ("** TEST PASSED **" in text
          and re.search(r"UVM_ERROR\s*:\s*0\b", text) is not None
          and re.search(r"UVM_FATAL\s*:\s*0\b", text) is not None)
    print(f"[{'PASS' if ok else 'FAIL'}] {test} seed={seed}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", default="dma_smoke_test")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--regress", action="store_true")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--no-compile", action="store_true")
    a = ap.parse_args()
    if not a.no_compile:
        compile_all()
    if a.regress:
        src = (ROOT / "tb" / "tests" / "dma_tests.svh").read_text()
        tests = re.findall(r"^`DMA_TEST\((\w+)\s*,", src, re.M)
        results = [run(t, s) for t in tests for s in range(1, a.seeds + 1)]
        print(f"{sum(results)}/{len(results)} passed")
        sys.exit(0 if all(results) else 1)
    sys.exit(0 if run(a.test, a.seed) else 1)


if __name__ == "__main__":
    main()
