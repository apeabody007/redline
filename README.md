<img src="docs/icon.png" width="128" alt="Redline">

# Redline

**A free, open source system monitor for Apple Silicon Macs that tells you when
your Mac is throttling.**

CPU, GPU, memory usage and die temperature in one always-on-top pill you can
park anywhere on screen, plus a throttle warning the moment macOS reports
thermal pressure.

<img src="docs/screenshot.png" width="700" alt="The Redline pill floating over a desktop, reading CPU 13%, GPU 11%, RAM 73%, 102°F">

No dock icon, one menu bar item, about 450 lines of Swift. Builds with the
Xcode Command Line Tools alone, so you do not need a 12 GB Xcode install to
compile it.

Every number is padded to a fixed width in a monospaced face, so the pill holds
its size as the readings move. A monitor that jitters in the corner of your eye
is worse than no monitor.

## Why another system monitor

Because the interesting number is not the temperature, it is whether the
machine is quietly slowing down. macOS reports thermal pressure through
`ProcessInfo.thermalState`, and sustained load on a fanless Mac will move it
long before anything feels wrong. Redline puts a `WARM` or `THROTTLE` tag in the
pill the moment that happens, so a long compile or a local model run that has
started down-clocking is visible instead of inferred.

That matters most on the fanless Macs. An M-series Air will hold peak speed for
five to fifteen minutes of sustained load and then quietly down-clock, and
nothing in the system tells you it happened. A long compile or a local LLM run
just gets slower.

If you want menu bar graphs, history, fan control and per-process breakdowns,
[Stats](https://github.com/exelban/stats) is excellent and free, and iStat Menus
is the polished paid option. Redline is deliberately one line of text and one
warning.

## Install

```
./build.sh install
```

That builds `Redline.app`, copies it to `/Applications`, and launches it. Drag the
pill wherever you want it; the position is remembered.

The menu bar item holds the rest: **Show HUD**, **Reset Position**, **Use
Fahrenheit**, and **Launch at Login**. Units default to whatever your region
uses and the toggle overrides it.

To build without installing:

```
./build.sh
```

The app icon is drawn in code by `tools/make-icon.swift`, each size rendered
natively rather than downsampled, so it stays sharp at 16pt. `./build.sh icon`
redraws `Resources/Redline.icns`.

## Command line

```
redline --once       one reading, printed and exit
redline --sensors    every temperature sensor this Mac exposes
```

`--sensors` is the one to run on a new machine. If it prints readings, the
temperature display works there.

## How it reads the hardware

| Metric | Source | Portable |
| --- | --- | --- |
| CPU | `host_processor_info` tick deltas | Public API, stable |
| Memory | `host_statistics64`, matching Activity Monitor's "used" | Public API, stable |
| GPU | IORegistry `IOAccelerator` → `Device Utilization %` | Documented key, present on Intel and every Apple Silicon generation so far |
| Thermal pressure | `ProcessInfo.thermalState` | Public API, stable |
| Die temperature | `IOHIDEventSystem`, resolved with `dlopen` | Private, best effort |

Only the last row is fragile. There is no public temperature API on Apple
Silicon and `powermetrics` needs root, so the symbols are looked up at runtime.
Nothing is hardcoded to a chip: Redline enumerates whatever sensors the machine
advertises on the temperature usage page, drops the battery, NAND, and
calibration sensors, and takes the hottest die reading that remains. On a Mac
where the lookup fails, the temperature is simply omitted and the throttle tag
carries the signal on its own.

That private lookup is also why this cannot ship on the Mac App Store, and why
the build is ad-hoc signed rather than notarized.

## Requirements

macOS 14 or later, Apple Silicon. Xcode Command Line Tools
(`xcode-select --install`).

## License

MIT
