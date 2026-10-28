#Requires -Version 5.1
BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\FanCurve.psd1'
    Import-Module $modulePath -Force
    $script:DefaultConfig = Get-FanCurveDefaultConfig
}

Describe 'FanCurve configuration' {
    It 'accepts the built-in default config' {
        $result = Test-FanCurveConfig -Config $script:DefaultConfig
        $result.Valid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'accepts the shipped example config' {
        $path = Join-Path $PSScriptRoot '..\config\fancurve.example.json'
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $config = ConvertTo-FanCurveHashtable -InputObject $json
        $result = Test-FanCurveConfig -Config $config
        $result.Valid | Should -BeTrue
    }

    It 'rejects a curve with fewer than two points' {
        $config = Get-FanCurveDefaultConfig
        $config['cpu']['curve'] = @(@{ temp = 50; percent = 30 })
        (Test-FanCurveConfig -Config $config).Valid | Should -BeFalse
    }

    It 'rejects decreasing temperatures' {
        $config = Get-FanCurveDefaultConfig
        $config['cpu']['curve'] = @(
            @{ temp = 70; percent = 50 }
            @{ temp = 60; percent = 70 }
        )
        $result = Test-FanCurveConfig -Config $config
        $result.Valid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'strictly increasing'
    }

    It 'rejects percentages that fall as temperature rises' {
        $config = Get-FanCurveDefaultConfig
        $config['cpu']['curve'] = @(
            @{ temp = 50; percent = 70 }
            @{ temp = 80; percent = 40 }
        )
        $result = Test-FanCurveConfig -Config $config
        $result.Valid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'must not decrease'
    }

    It 'rejects an invalid smoothing value' {
        $config = Get-FanCurveDefaultConfig
        $config['cpu']['smoothing'] = 0
        (Test-FanCurveConfig -Config $config).Valid | Should -BeFalse
    }

    It 'rejects hysteresis where enter is not greater than exit' {
        $config = Get-FanCurveDefaultConfig
        $config['gpu']['hysteresis']['enter'] = 50
        $config['gpu']['hysteresis']['exit'] = 60
        $result = Test-FanCurveConfig -Config $config
        $result.Valid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'greater than exit'
    }

    It 'rejects a hysteresis temperature outside the sensor range' {
        $config = Get-FanCurveDefaultConfig
        $config['gpu']['hysteresis']['enter'] = 130
        $result = Test-FanCurveConfig -Config $config
        $result.Valid | Should -BeFalse
        ($result.Errors -join ' ') | Should -Match 'enter must be between 0 and 120'
    }

    It 'throws when an explicit config path is missing' {
        { Import-FanCurveConfig -Path (Join-Path $TestDrive 'does-not-exist.json') } |
            Should -Throw '*was not found*'
    }

    It 'rejects a config with no enabled fans' {
        $config = Get-FanCurveDefaultConfig
        $config['fans']['cpu'] = $null
        $config['fans']['gpu'] = $null
        (Test-FanCurveConfig -Config $config).Valid | Should -BeFalse
    }

    It 'merges nested overrides and keeps defaults' {
        $base = Get-FanCurveDefaultConfig
        $merged = Merge-FanCurveConfig -Base $base -Override @{
            pollSeconds = 5
            cpu = @{ smoothing = 0.5 }
        }
        $merged['pollSeconds'] | Should -Be 5
        $merged['cpu']['smoothing'] | Should -Be 0.5
        $merged['cpu']['maxStepUp'] | Should -Be 3
    }

    It 'creates an independent default config each call' {
        $left = Get-FanCurveDefaultConfig
        $right = Get-FanCurveDefaultConfig
        $left['cpu']['smoothing'] = 0.9
        $right['cpu']['smoothing'] | Should -Be 0.2
    }
}

Describe 'Fan curve interpolation' {
    It 'clamps below the first point' {
        Get-FanCurveTarget -Temperature 30 -Points $script:DefaultConfig['cpu']['curve'] | Should -Be 30
    }

    It 'returns the first point exactly' {
        Get-FanCurveTarget -Temperature 50 -Points $script:DefaultConfig['cpu']['curve'] | Should -Be 30
    }

    It 'interpolates linearly between points' {
        Get-FanCurveTarget -Temperature 67.5 -Points $script:DefaultConfig['cpu']['curve'] | Should -Be 65
    }

    It 'clamps above the last point' {
        Get-FanCurveTarget -Temperature 95 -Points $script:DefaultConfig['cpu']['curve'] | Should -Be 100
    }

    It 'uses the GPU curve for a high GPU temperature' {
        Get-FanCurveTarget -Temperature 67 -Points $script:DefaultConfig['gpu']['curve'] | Should -Be 80
    }

    It 'throws when a curve has too few points' {
        { Get-FanCurveTarget -Temperature 60 -Points @(@{ temp = 50; percent = 30 }) } | Should -Throw
    }
}

Describe 'Fan speed stepping' {
    It 'limits an upward step' {
        Get-FanCurveSteppedSpeed -Current 50 -Target 80 -Temperature 70 -EmergencyTemp 88 -MaxStepUp 3 -MaxStepDown 2 | Should -Be 53
    }

    It 'limits a downward step' {
        Get-FanCurveSteppedSpeed -Current 50 -Target 30 -Temperature 60 -EmergencyTemp 88 -MaxStepUp 3 -MaxStepDown 2 | Should -Be 48
    }

    It 'does not move when the target is current' {
        Get-FanCurveSteppedSpeed -Current 50 -Target 50 -Temperature 60 -EmergencyTemp 88 -MaxStepUp 3 -MaxStepDown 2 | Should -Be 50
    }

    It 'jumps directly to the target in an emergency' {
        Get-FanCurveSteppedSpeed -Current 30 -Target 100 -Temperature 90 -EmergencyTemp 88 -MaxStepUp 3 -MaxStepDown 2 | Should -Be 100
    }

    It 'clamps values to the 0-100 range' {
        Get-FanCurveSteppedSpeed -Current 99 -Target 120 -Temperature 50 -EmergencyTemp 88 -MaxStepUp 3 -MaxStepDown 2 | Should -Be 100
    }
}

Describe 'Hysteresis' {
    It 'stays quiet below the exit temperature' {
        Get-FanCurveHysteresisState -CurrentState $true -Temperature 55 -Enter 62 -Exit 56 | Should -BeFalse
    }

    It 'enters the high state at the enter temperature' {
        Get-FanCurveHysteresisState -CurrentState $false -Temperature 62 -Enter 62 -Exit 56 | Should -BeTrue
    }

    It 'holds the previous state between exit and enter' {
        Get-FanCurveHysteresisState -CurrentState $true -Temperature 59 -Enter 62 -Exit 56 | Should -BeTrue
        Get-FanCurveHysteresisState -CurrentState $false -Temperature 59 -Enter 62 -Exit 56 | Should -BeFalse
    }
}

Describe 'Acer WMI encoding' {
    It 'packs a fan speed as (percent << 8) | fan id' {
        ('0x{0:X}' -f (Get-FanSpeedInput -FanId 1 -Percent 70)) | Should -Be '0x4601'
        ('0x{0:X}' -f (Get-FanSpeedInput -FanId 4 -Percent 30)) | Should -Be '0x1E04'
    }

    It 'packs a custom CPU and GPU behavior' {
        ('0x{0:X}' -f (Get-FanBehaviorInput -FanBitmap 9 -CpuMode 3 -GpuMode 3)) | Should -Be '0xC30009'
    }

    It 'packs an AUTO CPU and GPU behavior' {
        ('0x{0:X}' -f (Get-FanBehaviorInput -FanBitmap 9 -CpuMode 1 -GpuMode 1)) | Should -Be '0x410009'
    }

    It 'packs a CPU-only behavior' {
        ('0x{0:X}' -f (Get-FanBehaviorInput -FanBitmap 1 -CpuMode 3 -GpuMode 1)) | Should -Be '0x30001'
    }

    It 'decodes a SysInfo temperature from bits 8-23' {
        (Get-FanSysInfoValue -Raw ([uint64]0x4E01)) | Should -Be 78
        (Get-FanSysInfoValue -Raw ([uint64]0x12345678)) | Should -Be 0x3456
    }

    It 'decodes CPU and GPU behavior modes' {
        $mode = Get-FanBehaviorMode -Raw ([uint64]0x0000C100)
        $mode.Status | Should -Be 0
        $mode.Cpu | Should -Be 1
        $mode.Gpu | Should -Be 3
    }

    It 'decodes a fan speed and status' {
        $speed = Get-FanSpeedValue -Raw ([uint64]0x4600)
        $speed.Status | Should -Be 0
        $speed.Percent | Should -Be 70
    }

    It 'builds the behavior bitmap from enabled fans' {
        (Get-FanCurveBehaviorBitmap -Config $script:DefaultConfig) | Should -Be 9
        $cpuOnly = Get-FanCurveDefaultConfig
        $cpuOnly['fans']['gpu'] = $null
        (Get-FanCurveBehaviorBitmap -Config $cpuOnly) | Should -Be 1
    }
}
