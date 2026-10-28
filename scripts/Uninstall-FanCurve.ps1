#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$KeepConfig,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot 'src\FanCurve.psd1'
    Import-Module $modulePath -Force

    if (-not (Test-FanCurveAdmin)) {
        if ($NoElevate) {
            throw 'Uninstall requires an elevated PowerShell session.'
        }

        $elevatedArguments = @('-NoElevate')
        if ($KeepConfig) { $elevatedArguments += '-KeepConfig' }

        Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
        $exitCode = Request-FanCurveElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArguments
        exit $exitCode
    }

    $result = Uninstall-FanCurve -KeepConfig:$KeepConfig

    Write-Host ''
    Write-Host 'FanCurve uninstalled.' -ForegroundColor Green
    Write-Host 'Fans are back on the firmware curve.'
    if ($result.ConfigKept) {
        Write-Host ("  Config kept: {0}" -f $result.DataPath) -ForegroundColor DarkGray
    }
}
catch {
    Write-Host ("Uninstall failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
