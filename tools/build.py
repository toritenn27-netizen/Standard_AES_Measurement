#!/usr/bin/env python3
"""Build Uno firmware without modifying the sketch or installed Arduino core."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def build(sketch, output, test=False):
    core_root = Path(os.environ.get(
        "ARDUINO_AVR_ROOT", "/usr/share/arduino/hardware/arduino/avr"))
    core = core_root / "cores/arduino"
    variant = core_root / "variants/standard"
    prefix = os.environ.get("AVR_PREFIX", "avr-")
    if not (core / "Arduino.h").is_file() or not shutil.which(prefix + "g++"):
        raise SystemExit("Set ARDUINO_AVR_ROOT and AVR_PREFIX, or install gcc-avr, "
                         "avr-libc, binutils-avr and arduino-core-avr.")
    output.mkdir(parents=True, exist_ok=True)
    flags = ["-mmcu=atmega328p", "-DF_CPU=16000000L", "-DARDUINO=10819",
             "-DARDUINO_AVR_UNO", "-DARDUINO_ARCH_AVR", "-Os", "-g",
             "-ffunction-sections", "-fdata-sections", "-I" + str(core),
             "-I" + str(variant)]
    archive = output / "core.a"
    archive.unlink(missing_ok=True)
    for source in sorted(core.iterdir()):
        if source.suffix not in (".c", ".cpp", ".S"):
            continue
        obj = output / (source.name + ".o")
        compiler = prefix + ("g++" if source.suffix == ".cpp" else "gcc")
        extra = (["-std=gnu++11", "-fno-exceptions", "-fno-threadsafe-statics"]
                 if source.suffix == ".cpp" else [])
        run(compiler, *flags, *extra, "-c", source, "-o", obj)
        run(prefix + "ar", "rcs", archive, obj)
    objects = []
    for source in sorted(sketch.iterdir()):
        if source.suffix not in (".ino", ".cpp", ".S"):
            continue
        obj = output / (source.name + ".o")
        if source.suffix == ".S":
            run(prefix + "gcc", *flags, "-c", source, "-o", obj)
        else:
            run(prefix + "g++", *flags, "-std=gnu++11", "-fno-exceptions",
                "-fno-threadsafe-statics", "-x", "c++", "-c", source, "-o", obj)
        objects.append(obj)
    extra_link = []
    if test:
        obj = output / "instrument.o"
        run(prefix + "g++", *flags, "-std=gnu++11", "-c",
            ROOT / "tests/instrument.cpp", "-o", obj)
        objects.append(obj)
        extra_link = ["-Wl,--wrap=delay", "-Wl,--wrap=digitalWrite"]
    elf = output / "firmware.elf"
    run(prefix + "g++", "-mmcu=atmega328p", "-Wl,--gc-sections",
        "-Wl,-Map=" + str(output / "firmware.map"), *extra_link,
        "-o", elf, *objects, archive, "-lm")
    run(prefix + "objcopy", "-O", "ihex", "-R", ".eeprom", elf,
        output / "firmware.hex")
    run(prefix + "size", elf)
    return elf


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sketch", type=Path,
                        default=ROOT / "Standard_AES_Measurement_ASM")
    parser.add_argument("--output", type=Path, default=ROOT / "build/uno")
    parser.add_argument("--test", action="store_true")
    args = parser.parse_args()
    build(args.sketch.resolve(), args.output.resolve(), args.test)
