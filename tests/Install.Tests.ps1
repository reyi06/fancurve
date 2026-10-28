#Requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\FanCurve.psd1') -Force

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:TempRoot = Join-Path $env:TEMP ("FanCurve-install-test-{0}" -f ([guid]::NewGuid().ToString('N')))
    $script:InstallPath = Join-Path $script:TempRoot 'Program'
    $script:DataPath = Join-Path $script:TempRoot 'Data'
}

AfterAll {
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Installer file layout' {
    It 'copies the program, schema and default config without registering a real task' {
        InModuleScope FanCurve -Parameters @{
            SourcePath  = $script:RepoRoot
            InstallPath = $script:InstallPath
            DataPath    = $script:DataPath
        } {
            param($SourcePath, $InstallPath, $DataPath)

            Mock Test-FanCurveAdmin { $true }
            Mock Get-ScheduledTask { $null }
            Mock Restore-AcerFanAuto { }
            Mock Register-FanCurveTask { }

            $result = Install-FanCurve -SourcePath $SourcePath -InstallPath $InstallPath -DataPath $DataPath -NoStart

            $result.InstallPath | Should -Be $InstallPath
            $result.DataPath | Should -Be $DataPath
            (Test-Path -LiteralPath (Join-Path $InstallPath 'fancurve.ps1')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $InstallPath 'src\FanCurve.psm1')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $InstallPath 'src\FanCurve.psd1')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $DataPath 'config.json')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $DataPath 'fancurve.schema.json')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $DataPath 'logs')) | Should -BeTrue

            $installed = Get-Content -LiteralPath (Join-Path $DataPath 'config.json') -Raw | ConvertFrom-Json
            $installed.fans.cpu | Should -Be 1
            $installed.fans.gpu | Should -Be 4
        }
    }

    It 'keeps the config when requested during uninstall' {
        InModuleScope FanCurve -Parameters @{
            InstallPath = $script:InstallPath
            DataPath    = $script:DataPath
        } {
            param($InstallPath, $DataPath)

            Mock Test-FanCurveAdmin { $true }
            Mock Get-ScheduledTask { $null }
            Mock Restore-AcerFanAuto { }
            Mock Unregister-FanCurveTask { }

            $result = Uninstall-FanCurve -InstallPath $InstallPath -DataPath $DataPath -KeepConfig

            $result.ConfigKept | Should -BeTrue
            (Test-Path -LiteralPath $InstallPath) | Should -BeFalse
            (Test-Path -LiteralPath $DataPath) | Should -BeTrue
        }
    }
}
