#!/usr/bin/env python3
"""Compile the separate Uno stage-test sketch, run simavr and verify its log."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build import build, run
from check_stages import check


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simavr-prefix', type=Path, default=Path('/usr'))
    args = parser.parse_args()
    directory = ROOT / 'build/stage-test'
    elf = build(ROOT / 'AES_Round1_Stage_Test_ASM', directory)
    multiarch = subprocess.check_output(['gcc', '-print-multiarch'], text=True).strip()
    lib = args.simavr_prefix / 'lib' / multiarch
    if not lib.is_dir():
        lib = args.simavr_prefix / 'lib'
    simulator = directory / 'simulate_stages'
    run('gcc', '-std=c11', '-Wall', '-Wextra', '-Werror',
        '-I' + str(args.simavr_prefix / 'include/simavr'), ROOT / 'tests/simulate_stages.c',
        '-L' + str(lib), '-Wl,-rpath,' + str(lib), '-lsimavr', '-o', simulator)
    run(simulator, elf, directory / 'serial.log', directory / 'stats.json')
    run(simulator, elf, directory / 'known_vector.log', directory / 'known_vector_stats.json', '--known-vector')
    check(directory)


if __name__ == '__main__':
    main()
