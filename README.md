# Hopscreen

Switch your monitor's input from the macOS menu bar — with global keyboard shortcuts. Free and open source.

Made for the common setup of **one monitor shared by two computers** (say a Mac Studio on HDMI and a MacBook on USB-C): press a shortcut on the computer you're using and the monitor hops to the other one. No need to reach for the monitor's buttons.

- One click in the menu bar to switch to any input
- Global shortcuts per input (no Accessibility permission needed)
- Works with multiple monitors; each one is identified by its EDID, so settings stay with the right screen
- Tiny native app, no dependencies, no background polling
- CLI for scripting: `Hopscreen --list`, `Hopscreen --set 0x11`

## Requirements

- A Mac with Apple Silicon, running macOS 13 or later
- A monitor with **DDC/CI** enabled (usually a setting in the monitor's on-screen menu)

## Install

Download `Hopscreen.zip` from [Releases](../../releases/latest), unzip it, and move `Hopscreen.app` to Applications.

If macOS says the app can't be opened (this happens for builds that aren't notarized yet), run:

```bash
xattr -dr com.apple.quarantine /Applications/Hopscreen.app
```

## Setup for two computers

Install Hopscreen on **both** computers. On each one, bind a shortcut to the **other** computer's input:

| On the… | Bind shortcut to | Example |
|---|---|---|
| Mac Studio (connected via HDMI) | USB-C | ⌃⌥⌘I |
| MacBook (connected via USB-C) | HDMI 1 | ⌃⌥⌘I |

Now the same shortcut always jumps to "the other computer".

Menu: **Hotkeys → *input* → Set Shortcut…**

## Finding the right input values

Monitors switch inputs through VCP code `0x60`. Standard values:

| Input | Value |
|---|---|
| DisplayPort 1 / 2 | `0x0F` / `0x10` |
| HDMI 1 / 2 | `0x11` / `0x12` |
| Thunderbolt / USB-C (many Dells) | `0x19` |
| USB-C (many Dells) | `0x1B` |

Hopscreen reads the current input when it first sees a monitor and adds it to the list. If an input doesn't work, use **Inputs → Read Current Input** while the monitor shows that input, then **Add Input…** with that value.

Tested monitors (PRs welcome):

| Monitor | Inputs |
|---|---|
| Dell U3225QE | HDMI `0x11`, Thunderbolt/USB-C `0x19` |

## Known limitations

- **Intel Macs** aren't supported.
- **The built-in HDMI port on M1 Macs** (Mac mini M1, M1 Mac Studio) doesn't support DDC. Use a USB-C/DisplayPort connection, or switch from the other computer.
- Some **LG** monitors use a non-standard input-switch command that isn't supported yet.
- Hopscreen uses a private macOS API (`IOAVService`, the same one used by [m1ddc](https://github.com/waydabber/m1ddc) and [MonitorControl](https://github.com/MonitorControl/MonitorControl)). A macOS update could break it.

## Build from source

```bash
scripts/build.sh --install
```

Requires Xcode command line tools. `scripts/release.sh` signs, notarizes and packages a release (see the notes at the top of the script).

## License

MIT
