@{
    RootModule        = 'FanCurve.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '0e58adb7-58b4-4bff-b75f-accfc7399897'
    Author            = 'reyi06'
    CompanyName       = 'reyi06'
    Copyright         = '(c) 2026 reyi06'
    Description       = 'Configurable fan curve controller for Acer Nitro and Predator laptops.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-FanCurveVersion',
        'Get-FanCurveInstallPath',
        'Get-FanCurveDataPath',
        'Get-FanCurveConfigPath',
        'Get-FanCurveLogPath',
        'Get-FanCurveDefaultConfig',
        'ConvertTo-FanCurveHashtable',
        'Merge-FanCurveConfig',
        'Test-FanCurveConfig',
        'Assert-FanCurveConfig',
        'Import-FanCurveConfig',
        'Get-FanCurveTarget',
        'Get-FanCurveSteppedSpeed',
        'Get-FanCurveHysteresisState',
        'Get-FanSpeedInput',
        'Get-FanBehaviorInput',
        'Get-FanSysInfoValue',
        'Get-FanBehaviorMode',
        'Get-FanSpeedValue',
        'Get-FanCurveBehaviorBitmap',
        'Test-FanCurveAdmin',
        'Get-AcerGamingInstance',
        'Invoke-AcerGamingMethod',
        'Get-AcerGamingSysInfo',
        'Get-AcerSupportedSensor',
        'Get-AcerFanMode',
        'Set-AcerFanMode',
        'Get-AcerFanSpeed',
        'Set-AcerFanSpeed',
        'Restore-AcerFanAuto',
        'Get-AcerSystemInfo',
        'Get-NitroSenseTemperature',
        'Get-FanCurveTemperature',
        'Start-FanCurveController',
        'Get-FanCurveTaskStatus',
        'Get-FanCurveStatus',
        'Format-FanCurveStatus',
        'Invoke-FanCurveDoctor',
        'Format-FanCurveDoctor',
        'Request-FanCurveElevation',
        'Register-FanCurveTask',
        'Unregister-FanCurveTask',
        'Install-FanCurve',
        'Uninstall-FanCurve',
        'Show-FanCurveHelp'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('acer', 'nitro', 'predator', 'fan', 'curve', 'wmi', 'windows')
            LicenseUri   = 'https://github.com/reyi06/fancurve/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/reyi06/fancurve'
            ReleaseNotes = 'Initial release.'
        }
    }
}
