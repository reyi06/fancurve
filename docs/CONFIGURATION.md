# Configuration

FanCurve reads a single JSON file. The installed path is:

```text
C:\ProgramData\FanCurve\config.json
```

When running from the repository without installing, the CLI looks for
`config\fancurve.json` first, then `config\fancurve.example.json`. Use
`-Config <path>` to point at another file.

After editing the installed config, restart the task from an elevated
PowerShell window:

```powershell
Restart-ScheduledTask -TaskName FanCurve
```

The controller reads the file only at startup. It does not reload it while
running.

## Complete example

```json
{
  "$schema": "./fancurve.schema.json",
  "version": 1,
  "pollSeconds": 2,
  "modeRefreshSeconds": 30,
  "statusLogSeconds": 60,
  "provider": "auto",
  "pauseOnTurboMode": true,
  "logLevel": "info",
  "fans": {
    "cpu": 1,
    "gpu": 4
  },
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
    "hysteresis": {
      "enter": 62,
      "exit": 56,
      "lowPercent": 30
    },
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

Unknown top-level fields are ignored. Unknown fields inside `fans`, `safety`,
and each fan object are not rejected by the controller, but the JSON schema
marks them as invalid.

## Top-level fields

### `version`

Current schema version. Use `1`.

### `pollSeconds`

How often the controller reads temperatures, in seconds. Minimum `1`, maximum
`60`. The default is `2`.

Shorter intervals react faster but create more WMI traffic. Longer intervals
are quieter for the CPU but may overshoot a fast temperature spike.

### `modeRefreshSeconds`

How often the controller re-applies custom fan mode, in seconds. Minimum `5`,
maximum `600`. The default is `30`.

Some firmware resets the fan mode after sleep/resume or a power profile change.
Re-applying it periodically keeps the curve active. Setting it too low adds
unnecessary WMI writes.

### `statusLogSeconds`

Heartbeat interval for the log. `0` disables the heartbeat. The default is `60`.
A line is always written when the applied fan speed changes, regardless of this
setting.

### `provider`

Selects the temperature source:

| Value | Behavior |
| --- | --- |
| `auto` | Try Acer WMI first; fall back to NitroSense. |
| `acer-wmi` | Require `GetGamingSysInfo`; fail if unavailable. |
| `nitrosense` | Read temperatures from the NitroSense window. |

`auto` is recommended. Fan writes always use Acer WMI, regardless of this
setting, because there is no other supported fan-control interface.

### `pauseOnTurboMode`

When `true`, the controller reads `GetGamingFanBehavior` and pauses while the
CPU mode is `2` (Turbo/Max). It resumes when the user selects another mode. This
prevents a fight with NitroSense's maximum-cooling mode.

### `logLevel`

`debug`, `info`, `warn`, or `error`. The default is `info`.

`debug` includes fan-mode read failures and other details that are normally
quiet. Use it while diagnosing a new model.

## Fan selection

### `fans.cpu` and `fans.gpu`

The Acer fan IDs used for speed reads and writes. On the tested AN515-57:

- CPU fan: `1`
- GPU fan: `4`

Set an entry to `null` to disable that fan. At least one fan must be enabled.

If `doctor` reports a status error for a fan ID, try another ID or disable that
fan. The behavior bitmap always uses bit 0 for the CPU fan and bit 3 for the GPU
fan; the IDs are separate values.

CPU-only example:

```json
"fans": {
  "cpu": 1,
  "gpu": null
}
```

## Curves

Each fan has a `curve` array:

```json
"curve": [
  { "temp": 50, "percent": 30 },
  { "temp": 70, "percent": 65 },
  { "temp": 85, "percent": 100 }
]
```

Rules:

1. At least two points.
2. Temperatures must be strictly increasing.
3. Percentages must not decrease as temperature rises.
4. Temperatures are Celsius, `0`–`120`.
5. Percentages are `0`–`100`.
6. Values between points are linearly interpolated.
7. Below the first point, the first percentage is used.
8. Above the last point, the last percentage is used.

The controller then clamps the result to `safety.minPercent` and
`safety.maxPercent`.

## Per-fan fields

### `smoothing`

Exponential moving average alpha, from `0.01` to `1.0`.

```text
smoothed = alpha * currentTemperature + (1 - alpha) * previousSmoothed
```

- `1.0`: no smoothing; use the current temperature.
- `0.2`: a slow, quiet response.
- `0.5`: a balanced response.

Smoothing applies to the temperature used for the curve. The emergency check
uses the raw temperature, so a sudden spike still triggers full speed.

### `maxStepUp` and `maxStepDown`

Maximum percentage change per poll. Minimum `1`, maximum `100`.

A low `maxStepUp` makes fan changes gradual but can lag a temperature spike.
The emergency temperature bypasses these limits.

### `emergencyTemp`

When the raw temperature reaches this value, the target is set to
`safety.maxPercent` immediately, ignoring smoothing and rate limits. The default
is `88` for CPU and `75` for GPU.

Set this above the temperature where you want full speed during normal
operation, but below the point where the machine throttles.

### `hysteresis`

Optional. Intended for the GPU fan, but allowed on either fan.

```json
"hysteresis": {
  "enter": 62,
  "exit": 56,
  "lowPercent": 30
}
```

- When the temperature is at or above `enter`, the fan enters the high state
  and follows the curve.
- When the temperature is at or below `exit`, the fan enters the quiet state
  and uses `lowPercent`.
- Between `exit` and `enter`, the previous state is held.

`enter` must be greater than `exit`. This prevents the fan from repeatedly
crossing one threshold.

If a fan has no hysteresis, its curve is evaluated every poll.

## Safety

### `safety.minPercent` and `safety.maxPercent`

Global clamps for every target, including hysteresis and fallback values.
Defaults are `30` and `100`.

A minimum of 30% is a conservative default for laptop fans. Lower values may
stop the fan on some models; only do that if you know the hardware supports it.

### `safety.fallbackPercent`

The speed applied to both fans after `failureThreshold` consecutive temperature
read failures. Default `70`.

The value is clamped to `minPercent` and `maxPercent`.

### `safety.failureThreshold`

Number of consecutive failed temperature reads before fallback. Minimum `1`,
maximum `60`. Default `6`.

At the default two-second poll interval, six failures is about twelve seconds.

### `safety.restoreAutoOnExit`

When `true`, restore the firmware's automatic fan mode on normal exit, task
stop, uninstall, and `restore`. Default `true`.

`-NoRestore` on the CLI overrides this for a manual run. Do not leave the
machine in custom mode after testing.

## Provider details

### Acer WMI

The controller calls `GetGamingSysInfo` with these sensor IDs:

| Sensor | ID |
| --- | --- |
| CPU temperature | `0x0101` |
| CPU fan RPM | `0x0201` |
| System temperature | `0x0301` |
| GPU fan RPM | `0x0601` |
| GPU temperature | `0x0A01` |

The reading is `(gmOutput >> 8) & 0xFFFF`. The value is validated before use:
CPU and GPU temperatures must be between 1 and 120 °C, and fan RPM must be
between 1 and 10,000. If the GPU temperature is unavailable, the GPU fan follows
CPU temperature and the log notes that it is estimated.

### NitroSense UI fallback

The fallback attaches to the NitroSense main window with UI Automation and looks
for `CPU` and `GPU` text labels followed by a plausible temperature. It also
reads the first two numbers followed by `RPM`.

NitroSense must be running with a real window. If it is minimized to the tray or
shows only fan control placeholders (`-`), the fallback may not find values.

## Validating a config

Run a dry run:

```powershell
.\fancurve.ps1 run -DryRun -Once -Config .\my-config.json
```

This reads temperatures, validates the file, computes one cycle of targets, and
writes nothing. Check the log for the computed percentages.

Run the doctor:

```powershell
.\fancurve.ps1 doctor -Config .\my-config.json
```

The config check uses the same validator as the controller.
