# Compatibility

FanCurve is built for Acer laptops that expose the `AcerGamingFunction` WMI
class. The interface is shared by many Nitro and Predator models, but individual
models and BIOS versions differ in which sensors and fan IDs they support.

## Tested

| Model | CPU | GPU | BIOS | OS | Notes |
| --- | --- | --- | --- | --- | --- |
| Acer Nitro AN515-57 | Intel Core i5-11400H | NVIDIA RTX 3050 Ti Laptop | V1.22 | Windows 11 26200 | CPU fan ID 1, GPU fan ID 4; `GetGamingSysInfo` present |

FanCurve's default curve and safety limits were tuned on this machine. The
tested fan IDs and sensor values come from the Acer WMI interface described in
the README.

## Likely compatible

- Acer Nitro 5 models from recent generations that include NitroSense and the
  `AcerGamingFunction` WMI class.
- Acer Predator Helios and Triton models with the same Acer gaming WMI
  interface.
- Models where `GetGamingSysInfo` is missing but the fan behavior and fan speed
  methods are present, using `"provider": "nitrosense"` and a running
  NitroSense window.
- CPU-only models, with `"fans": { "cpu": 1, "gpu": null }`.

This is not a guarantee. The fan IDs, supported modes, and sensor IDs can change
between models. Always run `doctor` before leaving the controller running.

## Not supported

- Non-Acer laptops.
- Acer desktops.
- Models without `AcerGamingFunction`.
- Machines where the Acer gaming WMI interface is disabled by the BIOS or
  missing a required Acer driver.
- Controlling the fan through a different embedded controller interface.

## Check a new machine

From an elevated PowerShell window:

```powershell
.\fancurve.ps1 doctor
```

The doctor is read-only. It reports:

- Manufacturer, model, BIOS, CPU and GPUs.
- Whether `AcerGamingFunction` exists.
- Whether the required methods are present.
- `GetGamingSysInfo` values for CPU/GPU temperature and fan RPM.
- Current fan behavior modes.
- Fan speed readback for the configured CPU and GPU IDs.
- Whether NitroSense is running with a readable window.
- Whether the fallback temperature provider works.
- Config validation.
- Scheduled task state.

Then run one dry cycle:

```powershell
.\fancurve.ps1 run -DryRun -Once
```

This reads temperatures and prints the calculated targets without writing fan
speeds.

Finally, test a short live run from an elevated window:

```powershell
.\fancurve.ps1 run -Once
```

`-Once` restores AUTO when it exits. Watch the log and listen to the fans. If the
fans do not change, or the controller stops with a write error, set the relevant
fan to `null` or stop and restore AUTO.

## Model-specific notes

### Fan IDs

The default IDs are CPU `1` and GPU `4`. To test another ID, edit
`config.json` and run `doctor`. A status error usually means the ID is not
supported on that model.

### CPU-only models

Set:

```json
"fans": {
  "cpu": 1,
  "gpu": null
}
```

FanCurve then uses behavior bitmap `0x1` instead of `0x9`. If the firmware
rejects the two-fan mode, the controller attempts CPU-only mode automatically
and logs a warning.

### Models without `GetGamingSysInfo`

Use the NitroSense provider:

```json
"provider": "nitrosense"
```

Keep NitroSense open on the monitoring page. The fallback reads the text
elements for CPU and GPU temperature and the first two RPM values.

### Turbo/Max mode

FanCurve pauses while the firmware reports CPU mode `2` (Turbo/Max). This is
intentional. If you want FanCurve to override that mode, set:

```json
"pauseOnTurboMode": false
```

Only do this if you understand how the model's firmware behaves. Some machines
treat Max mode as a hardware safety state.

### Sleep and resume

Some firmware versions reset the fan mode after sleep or a power profile change.
FanCurve re-applies custom mode every `modeRefreshSeconds`. If the fans still
revert, lower that value or restart the task after resume.

## Reporting a new model

Open an issue with:

1. The model number and BIOS version.
2. Windows version and build.
3. PowerShell version.
4. NitroSense version, if installed.
5. The output of `.\fancurve.ps1 doctor -Json`.
6. Any relevant log lines from
   `C:\ProgramData\FanCurve\logs\fancurve.log`.

Remove personal paths, usernames, and serial numbers before posting.

A useful report looks like:

```text
Model: Acer Nitro AN515-57
BIOS: V1.22
OS: Windows 11 26200
PowerShell: 7.6.9
NitroSense: 4.x
Result: works; CPU fan 1, GPU fan 4, SysInfo sensors present
```
