#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoStart,
    [switch]$ResetConfig,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot 'src\FanCurve.psd1'
    Import-Module $modulePath -Force

    if (-not (Test-FanCurveAdmin)) {
        if ($NoElevate) {
            throw 'Install requires an elevated PowerShell session.'
        }

        $elevatedArguments = @('-NoElevate')
        if ($NoStart) { $elevatedArguments += '-NoStart' }
        if ($ResetConfig) { $elevatedArguments += '-ResetConfig' }

        Write-Host 'Requesting administrator rights...' -ForegroundColor Yellow
        $exitCode = Request-FanCurveElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArguments
        exit $exitCode
    }

    $result = Install-FanCurve -SourcePath $repoRoot -NoStart:$NoStart -ResetConfig:$ResetConfig

    Write-Host ''
    Write-Host 'FanCurve installed.' -ForegroundColor Green
    Write-Host ("  Program: {0}" -f $result.InstallPath)
    Write-Host ("  Config:  {0}" -f $result.ConfigPath)
    Write-Host ("  Task:    {0}" -f $result.TaskName)
    if ($result.Started) {
        Write-Host '  The controller was started.' -ForegroundColor DarkGray
    }
    else {
        Write-Host '  The task was registered but not started (-NoStart).' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host 'Check it with:  .\fancurve.ps1 status' -ForegroundColor DarkGray
}
catch {
    Write-Host ("Install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
