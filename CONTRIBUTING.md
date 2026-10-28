# Contributing to FanCurve

Thanks for taking a look. FanCurve is a small PowerShell project, and hardware
reports are especially useful because Acer's WMI interface varies by model.

## Before you start

- Read the [configuration](docs/CONFIGURATION.md) and
  [compatibility](docs/COMPATIBILITY.md) docs.
- Run `.\fancurve.ps1 doctor` on the machine you are testing.
- Do not commit personal paths, logs, or machine serial numbers.
- Do not test fan writes on a machine you cannot afford to overheat. Use a dry
  run first.

## Development setup

1. Clone the repository.
2. Open PowerShell 7 or Windows PowerShell 5.1.
3. Import the module directly:

   ```powershell
   Import-Module .\src\FanCurve.psd1 -Force
   ```

4. Run a dry cycle:

   ```powershell
   .\fancurve.ps1 run -DryRun -Once
   ```

## Tests

The tests use Pester 5. PowerShell 7 is recommended.

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force
Invoke-Pester -Path .\tests -Output Detailed
```

To run the same parser check as CI:

```powershell
$files = Get-ChildItem -Recurse -File -Include *.ps1,*.psm1,*.psd1
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors) { $errors | Format-List }
}
```

Static analysis is optional but useful:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.psscriptanalyzer.psd1 -Severity Warning
```

## Code style

- Keep PowerShell 5.1 compatibility. Avoid PowerShell 7-only syntax in shipped
  code.
- Use four-space indentation and approved PowerShell verbs.
- Keep WMI encoding and safety logic covered by tests.
- Prefer small functions with explicit parameters over globals.
- Use `Write-Host` only for the CLI's human-facing output. Log through
  `Write-FanCurveLog`.
- Do not add third-party binaries or require administrator-only tooling for the
  tests.

## Hardware changes

If you change WMI behavior, fan packing, or the controller loop:

1. Add or update a unit test for the encoding logic.
2. Run `doctor` and a dry run on real hardware.
3. Run one live cycle with `run -Once` and confirm AUTO is restored.
4. Include the model, BIOS, Windows build, and relevant log lines in the pull
   request.

Do not include a live fan write in the automated test suite.

## Pull requests

- Keep the change focused.
- Update the README or docs when behavior or configuration changes.
- Update `CHANGELOG.md` for user-visible changes.
- Make sure the parser check and Pester tests pass.
- Describe what hardware you tested, if any.
