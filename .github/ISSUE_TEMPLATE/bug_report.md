---
name: Bug report
about: Report a problem with FanCurve
title: "[Bug]: "
labels: bug
assignees: ''
---

## What happened?

<!-- Describe the problem and what you expected instead. -->

## Machine

- **Model:** (for example, Acer Nitro AN515-57)
- **BIOS:**
- **Windows version and build:**
- **PowerShell version:**
- **NitroSense version:**
- **FanCurve version:**

## Diagnostic output

Run these from an elevated PowerShell window and paste the result:

```powershell
.\fancurve.ps1 doctor -Json
.\fancurve.ps1 status -Json
```

```json
<!-- Paste doctor/status JSON here. Remove personal paths if needed. -->
```

## Log

```text
<!-- Paste the last 50-100 lines of C:\ProgramData\FanCurve\logs\fancurve.log -->
```

## Checklist

- [ ] I ran `.\fancurve.ps1 doctor`.
- [ ] I tried a dry run with `.\fancurve.ps1 run -DryRun -Once`.
- [ ] I checked the [troubleshooting guide](../../docs/TROUBLESHOOTING.md).
- [ ] I am not running another fan-control utility at the same time.
- [ ] I removed serial numbers and personal paths from this report.
