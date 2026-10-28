#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'status', 'doctor', 'install', 'uninstall', 'restore', 'version', 'help')]
    [string]$Command = 'help',

    [string]$Config,
    [string]$LogPath,

    [ValidateSet('debug', 'info', 'warn', 'error')]
    [string]$LogLevel,

    [switch]$DryRun,
    [switch]$Once,
    [switch]$NoRestore,
    [switch]$Json,
    [switch]$NoStart,
    [switch]$ResetConfig,
    [switch]$KeepConfig,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'src\FanCurve.psd1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        $modulePath = Join-Path $PSScriptRoot 'src\FanCurve.psm1'
    }
    Import-Module $modulePath -Force

    if ($Config -and -not (Test-Path -LiteralPath $Config)) {
        throw "Config file '$Config' was not found."
    }
    $configPath = if ($Config) { $Config } else { Get-FanCurveConfigPath }
    $logPath = if ($LogPath) { $LogPath } else { Get-FanCurveLogPath }
    $isAdmin = Test-FanCurveAdmin

    switch ($Command) {
        'version' {
            Get-FanCurveVersion
            break
        }

        'help' {
            Show-FanCurveHelp
            break
        }

        'run' {
            $configObject = Import-FanCurveConfig -Path $configPath
            $runParameters = @{
                Config     = $configObject
                ConfigPath = $configPath
                LogPath    = $logPath
                DryRun     = $DryRun
                Once       = $Once
                NoRestore  = $NoRestore
            }
            if ($LogLevel) {
                $runParameters['LogLevel'] = $LogLevel
            }
            Start-FanCurveController @runParameters
            break
        }

        'status' {
            $status = Get-FanCurveStatus -ConfigPath $configPath
            if ($Json) {
                $status | ConvertTo-Json -Depth 8
            }
            else {
                Format-FanCurveStatus -Status $status
            }
            break
        }

        'doctor' {
            $result = Invoke-FanCurveDoctor -ConfigPath $configPath
            if ($Json) {
                $result | ConvertTo-Json -Depth 8
            }
            else {
                Format-FanCurveDoctor -Result $result
            }
            break
        }

        'restore' {
            if (-not $isAdmin) {
                if ($NoElevate) {
                    throw 'Restoring AUTO mode requires administrator privileges.'
                }
                Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
                $exitCode = Request-FanCurveElevation -ScriptPath $PSCommandPath -ArgumentList @('restore', '-NoElevate')
                exit $exitCode
            }

            $task = Get-ScheduledTask -TaskName 'FanCurve' -ErrorAction SilentlyContinue
            if ($task) {
                if ($task.State -eq 'Running') {
                    Stop-ScheduledTask -TaskName 'FanCurve' -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
            }
            Restore-AcerFanAuto -Console
            break
        }

        'install' {
            if (-not $isAdmin) {
                if ($NoElevate) {
                    throw 'Installing FanCurve requires administrator privileges.'
                }
                Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
                $exitCode = Request-FanCurveElevation -ScriptPath $PSCommandPath -ArgumentList @('install', '-NoElevate')
                exit $exitCode
            }

            $result = Install-FanCurve -SourcePath $PSScriptRoot -NoStart:$NoStart -ResetConfig:$ResetConfig
            Write-Host ''
            Write-Host 'FanCurve installed.' -ForegroundColor Green
            Write-Host ("  Program: {0}" -f $result.InstallPath)
            Write-Host ("  Config:  {0}" -f $result.ConfigPath)
            Write-Host ("  Task:    {0}" -f $result.TaskName)
            if ($result.Started) {
                Write-Host '  The controller was started. Use "fancurve.ps1 status" to check it.' -ForegroundColor DarkGray
            }
            break
        }

        'uninstall' {
            if (-not $isAdmin) {
                if ($NoElevate) {
                    throw 'Uninstalling FanCurve requires administrator privileges.'
                }
                Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
                $exitCode = Request-FanCurveElevation -ScriptPath $PSCommandPath -ArgumentList @('uninstall', '-NoElevate')
                exit $exitCode
            }

            $result = Uninstall-FanCurve -KeepConfig:$KeepConfig
            Write-Host ''
            Write-Host 'FanCurve uninstalled. Fans are back on the firmware curve.' -ForegroundColor Green
            if ($result.ConfigKept) {
                Write-Host ("  Config kept: {0}" -f $result.DataPath) -ForegroundColor DarkGray
            }
            break
        }
    }
}
catch {
    Write-Host ("FanCurve: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
