# Troubleshooting

Start with:

```powershell
.\fancurve.ps1 doctor
.\fancurve.ps1 status
```

The doctor is read-only and works without elevation, but the full hardware probe
requires an elevated terminal. The status command reports the task state and
the current mode/speeds when elevated.

## First checks

### Is the task installed and running?

```powershell
Get-ScheduledTask -TaskName FanCurve | Format-List TaskName,State
Get-ScheduledTaskInfo -TaskName FanCurve | Format-List LastRunTime,LastTaskResult,NextRunTime
```

`LastTaskResult` values:

| Value | Meaning |
| --- | --- |
| `0` | Last run succeeded |
| `267008` | Ready |
| `267009` | Running |
| `267011` | Never run |
| other | Hex error code |

### Is the log recording?

```powershell
Get-Content C:\ProgramData\FanCurve\logs\fancurve.log -Tail 100
```

The log rotates at 2 MB and keeps three backups. If the file is not being
written, check that the task is running as the user who installed it.

### Is NitroSense interfering?

NitroSense can change the fan mode, power profile, or Max mode. FanCurve pauses
when the firmware reports Turbo/Max mode if `pauseOnTurboMode` is `true` (the
default). Switch NitroSense to a normal profile or set the option to `false` if
you want FanCurve to take over.

## Common errors

### `Access denied` reading `AcerGamingFunction`

Fan writes and WMI reads require elevation.

1. Open PowerShell with **Run as administrator**.
2. Run `.\fancurve.ps1 doctor`.
3. If it still fails, the Acer WMI interface is not available to this account or
   the machine does not expose it.

### `AcerGamingFunction was not found`

The WMI class is not registered. Possible causes:

- The laptop is not an Acer Nitro/Predator model with the gaming WMI interface.
- A required Acer driver or service is missing.
- The BIOS exposes a different interface.

Install or repair NitroSense and the Acer drivers, reboot, and run `doctor`
again. FanCurve cannot control fans without this interface.

### `GetGamingSysInfo` returns status errors

The model exposes fan control but not the SysInfo sensor method. Set:

```json
"provider": "nitrosense"
```

Keep NitroSense running. If the fallback also fails, use `doctor -Json` to record
what is available.

### `No temperature provider is available`

Both Acer WMI and NitroSense failed. Check:

- Is NitroSense running with a visible window?
- Does `doctor` show a working `Temperature probe`?
- Are you elevated?
- Is the selected `provider` value valid?

For testing without hardware sensors, use a machine that exposes the interface;
there is no synthetic provider.

### `Another FanCurve controller is already running`

Only one controller can run per Windows session. This usually means the
scheduled task is already running. Check:

```powershell
Get-ScheduledTask -TaskName FanCurve | Format-List State
Get-Process pwsh | Select-Object Id,StartTime,Path
```

Stop the task before starting a manual controller:

```powershell
Stop-ScheduledTask -TaskName FanCurve
```

### `Fan writes failed three cycles in a row`

The controller restores AUTO and exits. Check the log for the exact fan ID and
status. Common causes:

- The configured `fans.cpu` or `fans.gpu` ID is wrong.
- The model does not support that fan.
- The firmware rejected custom mode.
- Another fan utility is writing at the same time.

Run `doctor`, correct the fan IDs or set an unsupported fan to `null`, then
restart the task.

### `SetGamingFanBehavior failed with status ...`

The firmware rejected the requested mode. Try:

- Setting `fans.gpu` to `null` for a CPU-only model.
- Setting `pauseOnTurboMode` to `false` if NitroSense is in Max mode.
- Restarting NitroSense, then retrying.
- Checking whether the model supports custom fan control at all.

### Fans keep returning to the firmware curve

- Verify the task is running.
- Lower `modeRefreshSeconds`.
- Check whether NitroSense is changing the mode.
- Check the log for repeated `Could not re-apply custom fan mode` warnings.
- After sleep/resume, restart the task if the firmware does not accept the
  re-applied mode.

### Fans are stuck at the fallback speed

The temperature provider is failing. Look for:

```text
Temperature read failed (1/6): ...
```

Fix the provider, then the controller returns to the curve. If the failures
continue, the fallback stays active by design.

### The laptop is louder than expected

- Raise the curve's low-temperature percentages? No: lower the percentages at
  low temperatures, but keep `minPercent` at a safe value.
- Increase `smoothing` (lower alpha) to reduce rapid changes.
- Increase `maxStepDown`? A higher step-down lets the fan slow faster. A lower
  value keeps it spinning longer.
- Check whether NitroSense's own profile is in Performance/Max mode.

### The laptop is hotter than expected

- Lower the curve temperatures or raise the percentages.
- Lower `emergencyTemp`.
- Check that the fans are actually changing with `status`.
- Clean the vents and confirm the laptop is on a hard surface.
- Stop FanCurve and restore AUTO to compare against the firmware curve.

## Manual recovery

### Restore AUTO

From an elevated PowerShell window:

```powershell
.\fancurve.ps1 restore
```

Or directly through WMI:

```powershell
$acer = Get-CimInstance -Namespace root\wmi -ClassName AcerGamingFunction
Invoke-CimMethod -InputObject $acer -MethodName SetGamingFanBehavior -Arguments @{ gmInput = [uint64]0x410009 }
```

`0x410009` sets both CPU and GPU to AUTO. For a CPU-only model, `0x10001` sets
CPU AUTO.

### Stop and remove the task

```powershell
Stop-ScheduledTask -TaskName FanCurve
Unregister-ScheduledTask -TaskName FanCurve -Confirm:$false
```

Then run the uninstaller if you also want to remove the files.

### Remove a stuck installation

From an elevated PowerShell window:

```powershell
Stop-ScheduledTask -TaskName FanCurve -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName FanCurve -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item 'C:\Program Files\FanCurve' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\FanCurve' -Recurse -Force -ErrorAction SilentlyContinue
```

Restore AUTO first if the fans are still in custom mode.

## Installation problems

### The installer opens a UAC prompt and then closes

The elevated process runs in a separate window. If it fails immediately, run the
installer from an already elevated PowerShell window:

```powershell
Start-Process powershell -Verb RunAs
```

Then:

```powershell
cd C:\path\to\fancurve
.\scripts\Install-FanCurve.ps1 -NoElevate
```

### Execution policy blocks the script

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-FanCurve.ps1
```

### The task runs but the controller exits immediately

Check the task result and the log. Common causes are a missing module file after
an incomplete copy, an invalid config, or a non-Acer machine. The log usually
has the exact error.

### The installer keeps an old config

This is intentional. The installer updates the program and task but preserves
`C:\ProgramData\FanCurve\config.json`. Use `-ResetConfig` to replace it with the
shipped example.

## Collecting a support bundle

From an elevated PowerShell window:

```powershell
.\fancurve.ps1 doctor -Json > "$env:TEMP\fancurve-doctor.json"
.\fancurve.ps1 status -Json > "$env:TEMP\fancurve-status.json"
Copy-Item C:\ProgramData\FanCurve\logs\fancurve.log "$env:TEMP\fancurve.log"
```

Review the files and remove personal paths or usernames before sharing. The
doctor output includes the model, BIOS, sensor values, and task state; it does
not include serial numbers or user account names.
