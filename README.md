<img src="docs/icon.png" width="128" alt="Redline">

# Redline

**A free, open source system monitor for Apple Silicon Macs that tells you when
your Mac is throttling.**

CPU, GPU, memory usage and die temperature in one always-on-top pill you can
park anywhere on screen, plus a throttle warning the moment macOS reports
thermal pressure.

<img src="docs/screenshot.png" width="700" alt="The Redline pill floating over a desktop, reading CPU 13%, GPU 11%, RAM 73%, 102°F">

No dock icon, one menu bar item, about 650 lines of Swift. Builds with the
Xcode Command Line Tools alone, so you do not need a 12 GB Xcode install to
compile it.

Every number is padded to a fixed width in a monospaced face, so the pill holds
its size as the readings move. A monitor that jitters in the corner of your eye
is worse than no monitor.

## Install

```
./build.sh install
```

That builds `Redline.app`, copies it to `/Applications`, and launches it. Drag the
pill wherever you want it; the position is remembered.

Drag it anywhere, including up into the menu bar or down over the Dock, since
it draws above both. It is held to the left and right edges of the display so
the readings cannot be cut off, and it walks itself back onto a real screen if
the display it was living on gets unplugged.

The menu bar item holds the rest:

- **Appearance** — Auto, Light or Dark. Auto follows the system.
- **Severity Colors** — values tint amber then red so the pill reads at a
  glance. CPU and GPU warm at 70% and go red at 90%. Memory is different: it
  tints by macOS's own pressure verdict, not by the percentage, because a Mac
  deliberately fills RAM with caches and compressed pages. 71% used can be
  perfectly healthy or can be thrashing, and the percentage alone cannot tell
  you which. Temperature ignores this toggle and always tracks thermal pressure.
- **Use Fahrenheit** — on by default, switch it off for Celsius.
- **Show HUD**, **Reset Position**, **Launch at Login**.

To build without installing:

```
./build.sh
```

`./build.sh test` runs the unit tests.

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
| Memory pressure | `kern.memorystatus_vm_pressure_level` | Public sysctl, stable |
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

## Cost of leaving it running

About 0.4 CPU-seconds per minute idle, roughly 0.7% of one core, and 40 MB
resident. It opens no network sockets at all and only ever reads: kernel
counters, the IO registry, and the HID sensors. The only thing it writes is its
own preferences.

Sensor names are resolved once at startup rather than every tick, and the
peripheral sensors are filtered out at startup too, which cut idle CPU by 62%
over the naive version that walked all 39 services every second.

## Uninstall

```
launchctl disable "gui/$(id -u)/dev.aaronpeabody.redline" 2>/dev/null
rm -rf /Applications/Redline.app
defaults delete dev.aaronpeabody.redline
```

The middle line is the only one that matters if you never turned on Launch at
Login. The last one clears the remembered position and menu settings.

## Requirements

macOS 14 or later, Apple Silicon. Xcode Command Line Tools
(`xcode-select --install`).

## License

MIT
