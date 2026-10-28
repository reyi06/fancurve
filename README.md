# FanCurve

A configurable, temperature-driven fan curve controller for Acer Nitro and
Predator laptops.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Tested on](https://img.shields.io/badge/tested%20on-Nitro%20AN515--57-blue)](#compatibility)

FanCurve replaces the fixed NitroSense fan curve with a curve you control. It
talks to Acer's `AcerGamingFunction` WMI interface directly: no kernel driver,
no background service, and no bundled third-party binaries.

```
100% ┤                              ╭────────
 85% ┤                         ╭────╯
 65% ┤                    ╭────╯
 45% ┤              ╭─────╯
 30% ┤──────────────╯
     └──────┬───────┬───────┬───────┬───────
           50      60      70      80      85 °C
```

## What it does

- **Per-fan curves.** CPU and GPU have independent temperature-to-percentage
  curves. Interpolation is linear and the curve is clamped at both ends.
- **Hysteresis.** The GPU fan can stay quiet below an exit temperature and only
  spin up after an enter temperature, instead of oscillating around one value.
- **Smoothing and rate limits.** CPU temperature is smoothed with an
  exponential moving average, and both fans have separate ramp-up and ramp-down
  limits.
- **Emergency cooling.** A configurable emergency temperature bypasses the rate
  limits and requests full speed immediately.
- **Fallback cooling.** If temperature reads fail repeatedly, both fans are set
  to a safe fallback percentage until readings recover.
- **AUTO restore.** The controller restores the firmware's automatic fan mode
  when it exits, is stopped, or is uninstalled.
- **No UI scraping by default.** Temperature and fan RPM come from Acer's
  `GetGamingSysInfo` WMI method. NitroSense UI Automation is used only as a
  fallback.
- **Diagnostics.** `doctor` checks the machine, WMI interface, sensors, config,
  NitroSense fallback and scheduled task. `status` shows the current state.
- **Installer.** Copies the program to `Program Files`, keeps configuration and
  logs in `ProgramData`, and registers a logon task with highest privileges.

## Documentation

- [Configuration](docs/CONFIGURATION.md) - every field, curve rules, profiles,
  smoothing, hysteresis, and safety behavior.
- [Compatibility](docs/COMPATIBILITY.md) - tested models, how to check a new
  machine, and model-specific notes.
- [Troubleshooting](docs/TROUBLESHOOTING.md) - task, WMI, NitroSense, fan write,
  and recovery problems.
- [Contributing](CONTRIBUTING.md) - development setup, tests, and hardware
  reporting.

## Requirements

- Windows 10 or Windows 11, 64-bit.
- PowerShell 5.1 or newer. PowerShell 7 is recommended.
- An Acer Nitro or Predator laptop that exposes the `AcerGamingFunction` WMI
  class.
- Administrator rights for fan writes and installation.
- NitroSense installed and running is recommended. It provides the fallback
  temperature source and is the easiest way to confirm that the Acer gaming
  interface is present.

FanCurve is **not** a replacement for NitroSense's monitoring UI, RGB controls,
power profiles, or GPU overclocking. It only controls the fan curve.

## Install

Clone the repository or download the ZIP, open PowerShell in the repository
folder, and run:

```powershell
.\scripts\Install-FanCurve.ps1
```

The installer requests administrator rights, copies FanCurve to
`C:\Program Files\FanCurve`, creates `C:\ProgramData\FanCurve`, installs the
default config, registers a scheduled task named `FanCurve`, and starts it.

You can also install through the main CLI:

```powershell
.\fancurve.ps1 install
```

If script execution is blocked, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-FanCurve.ps1
```

The task runs at logon with highest privileges and a 30-second delay. Re-running
the installer updates the program and the task but keeps your existing
`config.json`. Use `-ResetConfig` to replace it with the shipped example.

## Quick start

```powershell
.\fancurve.ps1 doctor          # check the machine and the Acer WMI interface
.\fancurve.ps1 status          # current temperatures, fan speeds and task state
.\fancurve.ps1 run -DryRun -Once
```

`run -DryRun` reads temperatures and calculates targets without writing to the
fans. It is the safest way to test a new curve.

The installed controller logs to:

```text
C:\ProgramData\FanCurve\logs\fancurve.log
```

## Configure

The installed configuration lives at:

```text
C:\ProgramData\FanCurve\config.json
```

Edit it from an elevated PowerShell window:

```powershell
Start-Process notepad.exe -Verb RunAs -ArgumentList 'C:\ProgramData\FanCurve\config.json'
```

Then restart the task from the same elevated window:

```powershell
Restart-ScheduledTask -TaskName FanCurve
```

The shipped config is a good starting point for an Acer Nitro:

```json
{
  "$schema": "./fancurve.schema.json",
  "pollSeconds": 2,
  "provider": "auto",
  "pauseOnTurboMode": true,
  "fans": { "cpu": 1, "gpu": 4 },
  "cpu": {
    "curve": [
      { "temp": 50, "percent": 30 },
      { "temp": 85, "percent": 100 }
    ],
    "smoothing": 0.2,
    "maxStepUp": 3,
    "maxStepDown": 2,
    "emergencyTemp": 88
  },
  "gpu": {
    "curve": [
      { "temp": 56, "percent": 40 },
      { "temp": 62, "percent": 60 },
      { "temp": 72, "percent": 100 },
      { "temp": 100, "percent": 100 }
    ],
    "hysteresis": { "enter": 62, "exit": 56, "lowPercent": 30 },
    "smoothing": 1.0,
    "maxStepUp": 8,
    "maxStepDown": 2,
    "emergencyTemp": 75
  },
  "safety": {
    "minPercent": 30,
    "maxPercent": 100,
    "fallbackPercent": 70,
    "failureThreshold": 6,
    "restoreAutoOnExit": true
  }
}
```

### Curve rules

- A curve needs at least two points.
- `temp` is in Celsius and must increase strictly from point to point.
- `percent` must not decrease as temperature rises.
- Values are linearly interpolated between points.
- The first point is used below its temperature; the last point is used above
  its temperature.
- `safety.minPercent` and `safety.maxPercent` clamp every target, including the
  hysteresis low value and the fallback value.

### Field reference

| Field | Default | Meaning |
| --- | --- | --- |
| `pollSeconds` | `2` | Seconds between temperature reads. |
| `modeRefreshSeconds` | `30` | How often to re-apply custom fan mode. |
| `statusLogSeconds` | `60` | Heartbeat log interval; `0` disables it. |
| `provider` | `auto` | `auto`, `acer-wmi`, or `nitrosense`. |
| `pauseOnTurboMode` | `true` | Pause while the firmware is in Turbo/Max mode. |
| `logLevel` | `info` | `debug`, `info`, `warn`, or `error`. |
| `fans.cpu` | `1` | CPU fan ID, or `null` to disable CPU control. |
| `fans.gpu` | `4` | GPU fan ID, or `null` to disable GPU control. |
| `cpu.curve` / `gpu.curve` | see above | Temperature-to-percentage points. |
| `smoothing` | `0.2` CPU / `1.0` GPU | EMA alpha from `0.01` to `1.0`; `1.0` disables smoothing. |
| `maxStepUp` | `3` CPU / `8` GPU | Maximum percentage increase per poll. |
| `maxStepDown` | `2` | Maximum percentage decrease per poll. |
| `emergencyTemp` | `88` CPU / `75` GPU | Temperature that bypasses rate limits. |
| `hysteresis.enter` | `62` GPU | GPU temperature that enters the high state. |
| `hysteresis.exit` | `56` GPU | GPU temperature that returns to the quiet state. |
| `hysteresis.lowPercent` | `30` GPU | GPU target while in the quiet state. |
| `safety.minPercent` | `30` | Lower clamp for all fan targets. |
| `safety.maxPercent` | `100` | Upper clamp for all fan targets. |
| `safety.fallbackPercent` | `70` | Speed used after repeated temperature failures. |
| `safety.failureThreshold` | `6` | Failed temperature reads before fallback. |
| `safety.restoreAutoOnExit` | `true` | Restore AUTO when the controller stops. |

The JSON schema is at [`config/fancurve.schema.json`](config/fancurve.schema.json).
Editors that support JSON Schema will validate the file while you edit it.

### Quiet profile

```json
{
  "cpu": {
    "curve": [
      { "temp": 55, "percent": 25 },
      { "temp": 75, "percent": 55 },
      { "temp": 90, "percent": 100 }
    ],
    "maxStepUp": 2,
    "maxStepDown": 2
  },
  "gpu": {
    "curve": [
      { "temp": 58, "percent": 30 },
      { "temp": 68, "percent": 60 },
      { "temp": 78, "percent": 100 }
    ],
    "hysteresis": { "enter": 68, "exit": 58, "lowPercent": 30 },
    "maxStepUp": 4
  }
}
```

### Performance profile

```json
{
  "cpu": {
    "curve": [
      { "temp": 45, "percent": 40 },
      { "temp": 70, "percent": 75 },
      { "temp": 82, "percent": 100 }
    ],
    "smoothing": 0.5,
    "maxStepUp": 8
  },
  "gpu": {
    "curve": [
      { "temp": 50, "percent": 40 },
      { "temp": 64, "percent": 80 },
      { "temp": 72, "percent": 100 }
    ],
    "hysteresis": { "enter": 64, "exit": 52, "lowPercent": 35 },
    "maxStepUp": 10
  }
}
```

### CPU-only models

If the machine has one fan, or if `doctor` reports that the GPU fan ID is not
supported, set the GPU entry to `null`:

```json
"fans": {
  "cpu": 1,
  "gpu": null
}
```

## CLI

```text
.\fancurve.ps1 run [-Config <path>] [-LogPath <path>] [-LogLevel <level>] [-DryRun] [-Once] [-NoRestore]
.\fancurve.ps1 status [-Config <path>] [-Json]
.\fancurve.ps1 doctor [-Config <path>] [-Json]
.\fancurve.ps1 install [-NoStart] [-ResetConfig] [-NoElevate]
.\fancurve.ps1 uninstall [-KeepConfig] [-NoElevate]
.\fancurve.ps1 restore [-NoElevate]
.\fancurve.ps1 version
.\fancurve.ps1 help
```

| Command | Purpose |
| --- | --- |
| `run` | Start the controller. Requires elevation unless `-DryRun`. |
| `status` | Show model, BIOS, mode, fan speeds, temperatures, task state. |
| `doctor` | Read-only hardware and configuration check. |
| `install` | Install to `Program Files` and register the task. |
| `uninstall` | Stop the task, restore AUTO, and remove the install. |
| `restore` | Stop the task and put the fans back on the firmware curve. |
| `version` | Print the version. |
| `help` | Print usage. |

| Option | Applies to | Meaning |
| --- | --- | --- |
| `-Config` | `run`, `status`, `doctor` | Use an alternate config file. |
| `-LogPath` | `run` | Write the controller log to another file. |
| `-LogLevel` | `run` | Override the config log level (`debug`, `info`, `warn`, `error`). |
| `-DryRun` | `run` | Compute and log targets without writing fans. |
| `-Once` | `run` | Run one cycle, then exit and restore AUTO. |
| `-NoRestore` | `run` | Leave custom mode active on exit. Not recommended. |
| `-Json` | `status`, `doctor` | Emit machine-readable JSON. |
| `-NoStart` | `install` | Register the task without starting it. |
| `-ResetConfig` | `install` | Replace the installed config with the example. |
| `-KeepConfig` | `uninstall` | Keep `C:\ProgramData\FanCurve`. |
| `-NoElevate` | `install`, `uninstall`, `restore` | Fail instead of requesting UAC. |

## How it works

FanCurve uses the `AcerGamingFunction` WMI class in `root\wmi`.

### Temperature and RPM

`GetGamingSysInfo` takes a sensor ID and returns a packed value. The sensor
reading is in bits 8–23:

| Sensor | Input | Meaning |
| --- | --- | --- |
| CPU temperature | `0x0101` | Degrees Celsius |
| CPU fan RPM | `0x0201` | RPM |
| System temperature | `0x0301` | Degrees Celsius |
| GPU fan RPM | `0x0601` | RPM |
| GPU temperature | `0x0A01` | Degrees Celsius |
| Supported sensors | `0x0000` | Capability bitmap |

```text
value = (gmOutput >> 8) & 0xFFFF
```

### Fan mode

`SetGamingFanBehavior` uses a packed input:

| Bits | Meaning |
| --- | --- |
| 0 | CPU fan in the behavior bitmap |
| 3 | GPU fan in the behavior bitmap |
| 16–17 | CPU mode: `1` auto, `2` turbo, `3` custom |
| 22–23 | GPU mode: `1` auto, `2` turbo, `3` custom |

The mode used for both fans is `0xC30009`; AUTO is `0x410009`.

`GetGamingFanBehavior` returns the current mode differently: CPU mode is in bits
8–9 and GPU mode is in bits 14–15.

### Fan speed

`SetGamingFanSpeed` takes:

```text
(percent << 8) | fanId
```

The CPU fan is ID `1` and the GPU fan is ID `4` on the tested Nitro. Both are
configurable. `GetGamingFanSpeed` returns the current percentage in bits 8–15.

### Safety behavior

1. Read temperature and fan RPM from Acer WMI. If that fails, try NitroSense UI
   Automation.
2. If temperature reads fail `failureThreshold` times, set both fans to
   `fallbackPercent`.
3. If a fan write fails three cycles in a row, restore AUTO and stop.
4. On normal exit, task stop, or uninstall, restore AUTO unless explicitly
   disabled.
5. While the firmware is in Turbo/Max mode (`pauseOnTurboMode`), do not fight
   it; wait until another mode is selected.

## Compatibility

**Tested on**

| Machine | CPU | GPU | BIOS | OS |
| --- | --- | --- | --- | --- |
| Acer Nitro AN515-57 | Intel Core i5-11400H | NVIDIA RTX 3050 Ti Laptop | V1.22 | Windows 11 26200 |

**Likely compatible:** Acer Nitro and Predator models that expose
`AcerGamingFunction` with the fan methods. Recent models usually also expose
`GetGamingSysInfo`; older models may only support the fan-control methods and
will use the NitroSense fallback for temperatures.

**Not supported:** desktops, non-Acer laptops, and Acer models where the WMI
class is absent. A CPU-only model can work with `"gpu": null`.

Run `.\fancurve.ps1 doctor` on a new machine. It reports the model, BIOS,
available WMI methods, sensor values, fan IDs, NitroSense state, config
validation, and scheduled task state.

If you want to add a model to the compatibility table, open an issue with the
output of:

```powershell
.\fancurve.ps1 doctor -Json
```

Remove any personal paths before posting.

## Safety

FanCurve writes to the embedded controller through Acer's firmware interface.
That is the same mechanism NitroSense uses, but it is still a privileged
hardware write.

- Use at your own risk. There is no warranty.
- This project is not affiliated with or endorsed by Acer.
- Do not run FanCurve alongside another fan-control utility.
- Keep `safety.minPercent` at 30% or higher unless you know the machine can
  safely stop its fans.
- Sustained 100% fan speed increases noise and fan wear.
- If the laptop overheats, stop the task and run `.\fancurve.ps1 restore`.
- Laptop firmware may override fan settings after sleep, resume, or a power
  profile change. The controller re-applies custom mode periodically.

## Troubleshooting

### `Access denied` or `AcerGamingFunction is not available`

Fan writes require elevation. Open PowerShell with **Run as administrator** and
retry. If the class is still missing, the machine does not expose Acer's gaming
WMI interface.

### `GetGamingSysInfo` sensors are unavailable

Some models expose fan control but not the SysInfo sensor method. Set:

```json
"provider": "nitrosense"
```

and keep NitroSense running. The NitroSense window must exist; a tray-only or
minimized-to-tray process may not expose the text elements FanCurve reads.

### NitroSense fallback finds no temperatures

Open NitroSense, leave it on the monitoring page, and run:

```powershell
.\fancurve.ps1 doctor
```

If the values still cannot be read, use the Acer WMI provider on a model that
supports `GetGamingSysInfo`, or use another monitoring source.

### Fans keep returning to the firmware curve

- Check that the scheduled task is running:
  `Get-ScheduledTask -TaskName FanCurve`.
- Check the log at `C:\ProgramData\FanCurve\logs\fancurve.log`.
- NitroSense may be in Turbo/Max mode. FanCurve pauses by design; switch
  NitroSense to a normal profile or set `"pauseOnTurboMode": false`.
- Re-apply custom mode more often by lowering `modeRefreshSeconds`.

### The task is not running

```powershell
Get-ScheduledTask -TaskName FanCurve | Format-List State
Get-ScheduledTaskInfo -TaskName FanCurve | Format-List
```

Then check the log. The task is installed for the user who ran the installer.
If that account changes, reinstall.

### Fans are stuck at the fallback percentage

The temperature provider is failing. Check the log for repeated
`Temperature read failed` messages. Run `doctor`, make sure NitroSense is
available if the Acer SysInfo sensors are unsupported, and confirm the selected
`provider` is correct.

### Restore AUTO manually

From an elevated PowerShell window:

```powershell
.\fancurve.ps1 restore
```

Or directly:

```powershell
$acer = Get-CimInstance -Namespace root\wmi -ClassName AcerGamingFunction
Invoke-CimMethod -InputObject $acer -MethodName SetGamingFanBehavior -Arguments @{ gmInput = [uint64]0x410009 }
```

### Logs and support

```powershell
.\fancurve.ps1 status -Json
.\fancurve.ps1 doctor -Json
Get-Content C:\ProgramData\FanCurve\logs\fancurve.log -Tail 100
```

## Uninstall

```powershell
.\scripts\Uninstall-FanCurve.ps1
```

or:

```powershell
.\fancurve.ps1 uninstall
```

This stops the task, restores AUTO, removes the scheduled task, and removes
`C:\Program Files\FanCurve`. The config and logs in `C:\ProgramData\FanCurve`
are removed too. Use `-KeepConfig` to keep them.

The installer replaces the scheduled task named `FanCurve`. It does not delete
other copies of an older FanCurve script in another folder. Verify the new
install first, then remove the old copy manually if you want.

## Repository layout

```text
fancurve/
├─ fancurve.ps1                 CLI entry point
├─ src/
│  ├─ FanCurve.psm1             controller, WMI, providers, installer
│  └─ FanCurve.psd1             module manifest
├─ config/
│  ├─ fancurve.example.json     default configuration
│  └─ fancurve.schema.json      JSON schema
├─ scripts/
│  ├─ Install-FanCurve.ps1
│  └─ Uninstall-FanCurve.ps1
├─ tests/
│  └─ FanCurve.Tests.ps1
├─ docs/
│  ├─ COMPATIBILITY.md
│  ├─ CONFIGURATION.md
│  └─ TROUBLESHOOTING.md
└─ .github/workflows/ci.yml
```

## Prior art

The WMI protocol used here is documented by the Linux kernel
[`acer-wmi`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/acer-wmi.c)
driver and by community projects including
[AeroForge](https://github.com/noahcabral/aeroforge-nitrosense-alternative) and
[Div Acer Manager Fan Controls](https://github.com/PXDiv/Div-Acer-Manager-Fan-Controls).
FanCurve is an independent PowerShell implementation and does not include code
or binaries from those projects.

## License

MIT. See [LICENSE](LICENSE).
