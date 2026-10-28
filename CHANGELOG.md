# Changelog

All notable changes to FanCurve are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-28

### Added

- Temperature-driven CPU and GPU fan curves with linear interpolation.
- Per-fan smoothing, ramp-up and ramp-down limits, and emergency temperatures.
- GPU hysteresis with separate enter and exit temperatures.
- Acer WMI temperature and fan RPM reads through `GetGamingSysInfo`.
- NitroSense UI Automation fallback when the Acer SysInfo sensors are not
  available.
- Automatic fallback fan speed when temperature reads fail repeatedly.
- Restore-to-AUTO on exit, stop, uninstall, and manual `restore`.
- Configurable fan IDs, poll interval, log level, and safety limits.
- `fancurve.ps1` CLI with `run`, `status`, `doctor`, `install`, `uninstall`,
  `restore`, `version`, and `help`.
- Logon scheduled task with highest privileges, restart-on-failure, and
  battery-safe settings.
- Installer and uninstaller with UAC self-elevation.
- JSON schema and editor validation for the configuration file.
- Pester tests and a Windows GitHub Actions workflow.
- Documentation for configuration, compatibility, troubleshooting, and the
  WMI protocol.
