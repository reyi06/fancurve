#Requires -Version 5.1
Set-StrictMode -Version 2.0

$script:FanCurveVersion = '1.0.0'
$script:FanCurveLogPath = $null
$script:FanCurveLogLevel = 'info'
$script:FanCurveLogMaxBytes = 2MB
$script:FanCurveLogKeep = 3

#region Logging

function Initialize-FanCurveLog {
    [CmdletBinding()]
    param(
        [string]$Path,
        [ValidateSet('debug', 'info', 'warn', 'error')]
        [string]$Level = 'info',
        [int]$MaxBytes = 2097152,
        [int]$Keep = 3
    )

    $script:FanCurveLogPath = $Path
    $script:FanCurveLogLevel = $Level
    $script:FanCurveLogMaxBytes = [Math]::Max(65536, $MaxBytes)
    $script:FanCurveLogKeep = [Math]::Max(1, $Keep)

    if ($Path) {
        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
}

function Invoke-FanCurveLogRotation {
    [CmdletBinding()]
    param()

    if (-not $script:FanCurveLogPath -or -not (Test-Path -LiteralPath $script:FanCurveLogPath)) {
        return
    }

    for ($index = $script:FanCurveLogKeep - 1; $index -ge 1; $index--) {
        $source = "$($script:FanCurveLogPath).$index"
        $destination = "$($script:FanCurveLogPath).$($index + 1)"
        if (Test-Path -LiteralPath $source) {
            Move-Item -LiteralPath $source -Destination $destination -Force -ErrorAction SilentlyContinue
        }
    }

    Move-Item -LiteralPath $script:FanCurveLogPath -Destination "$($script:FanCurveLogPath).1" -Force -ErrorAction SilentlyContinue
}

function Write-FanCurveLog {
    [CmdletBinding()]
    param(
        [ValidateSet('debug', 'info', 'warn', 'error')]
        [string]$Level = 'info',
        [Parameter(Mandatory)]
        [string]$Message,
        [switch]$Console
    )

    $levels = @{ debug = 10; info = 20; warn = 30; error = 40 }
    if ($levels[$Level] -lt $levels[$script:FanCurveLogLevel]) {
        return
    }

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    if ($script:FanCurveLogPath) {
        try {
            if ((Test-Path -LiteralPath $script:FanCurveLogPath) -and
                ((Get-Item -LiteralPath $script:FanCurveLogPath).Length -ge $script:FanCurveLogMaxBytes)) {
                Invoke-FanCurveLogRotation
            }
            Add-Content -LiteralPath $script:FanCurveLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "FanCurve could not write its log: $($_.Exception.Message)"
        }
    }

    if ($Console) {
        switch ($Level) {
            'debug' { Write-Host $line -ForegroundColor DarkGray }
            'warn'  { Write-Host $line -ForegroundColor Yellow }
            'error' { Write-Host $line -ForegroundColor Red }
            default { Write-Host $line }
        }
    }
}

#endregion

#region Configuration

function Get-FanCurveVersion {
    [CmdletBinding()]
    param()
    return $script:FanCurveVersion
}

function Get-FanCurveInstallPath {
    [CmdletBinding()]
    param()
    $root = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }
    return (Join-Path $root 'FanCurve')
}

function Get-FanCurveDataPath {
    [CmdletBinding()]
    param()
    $root = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    return (Join-Path $root 'FanCurve')
}

function Get-FanCurveConfigPath {
    [CmdletBinding()]
    param()

    if ($env:FANCURVE_CONFIG -and (Test-Path -LiteralPath $env:FANCURVE_CONFIG)) {
        return (Resolve-Path -LiteralPath $env:FANCURVE_CONFIG).Path
    }

    $installed = Join-Path (Get-FanCurveDataPath) 'config.json'
    if (Test-Path -LiteralPath $installed) {
        return $installed
    }

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $repoConfig = Join-Path $repoRoot 'config\fancurve.json'
    if (Test-Path -LiteralPath $repoConfig) {
        return $repoConfig
    }

    $example = Join-Path $repoRoot 'config\fancurve.example.json'
    if (Test-Path -LiteralPath $example) {
        return $example
    }

    return $null
}

function Get-FanCurveLogPath {
    [CmdletBinding()]
    param()

    $dataPath = Get-FanCurveDataPath
    if (Test-Path -LiteralPath $dataPath) {
        return (Join-Path $dataPath 'logs\fancurve.log')
    }

    $repoRoot = Split-Path -Parent $PSScriptRoot
    return (Join-Path $repoRoot 'logs\fancurve.log')
}

function Get-FanCurveDefaultConfig {
    [CmdletBinding()]
    param()

    return @{
        version = 1
        pollSeconds = 2
        modeRefreshSeconds = 30
        statusLogSeconds = 60
        provider = 'auto'
        pauseOnTurboMode = $true
        logLevel = 'info'
        fans = @{
            cpu = 1
            gpu = 4
        }
        cpu = @{
            curve = @(
                @{ temp = 50; percent = 30 }
                @{ temp = 85; percent = 100 }
            )
            smoothing = 0.2
            maxStepUp = 3
            maxStepDown = 2
            emergencyTemp = 88
        }
        gpu = @{
            curve = @(
                @{ temp = 56; percent = 40 }
                @{ temp = 62; percent = 60 }
                @{ temp = 72; percent = 100 }
                @{ temp = 100; percent = 100 }
            )
            hysteresis = @{
                enter = 62
                exit = 56
                lowPercent = 30
            }
            smoothing = 1.0
            maxStepUp = 8
            maxStepDown = 2
            emergencyTemp = 75
        }
        safety = @{
            minPercent = 30
            maxPercent = 100
            fallbackPercent = 70
            failureThreshold = 6
            restoreAutoOnExit = $true
        }
    }
}

function ConvertTo-FanCurveHashtable {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-FanCurveHashtable -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-FanCurveHashtable -InputObject $property.Value
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-FanCurveHashtable -InputObject $item))
        }
        return ,$list.ToArray()
    }

    return $InputObject
}

function Merge-FanCurveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,
        [Parameter(Mandatory)]
        [hashtable]$Override
    )

    foreach ($key in $Override.Keys) {
        $value = $Override[$key]
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $value -is [hashtable]) {
            [void](Merge-FanCurveConfig -Base $Base[$key] -Override $value)
        }
        else {
            $Base[$key] = $value
        }
    }

    return $Base
}

function Test-FanCurveNumber {
    [CmdletBinding()]
    param($Value)
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal])
}

function Test-FanCurveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if (-not (Test-FanCurveNumber $Config['pollSeconds']) -or
        [double]$Config['pollSeconds'] -lt 1 -or [double]$Config['pollSeconds'] -gt 60) {
        [void]$errors.Add('pollSeconds must be a number between 1 and 60.')
    }

    if (-not (Test-FanCurveNumber $Config['modeRefreshSeconds']) -or
        [double]$Config['modeRefreshSeconds'] -lt 5 -or [double]$Config['modeRefreshSeconds'] -gt 600) {
        [void]$errors.Add('modeRefreshSeconds must be a number between 5 and 600.')
    }

    if (-not (Test-FanCurveNumber $Config['statusLogSeconds']) -or
        [double]$Config['statusLogSeconds'] -lt 0 -or [double]$Config['statusLogSeconds'] -gt 3600) {
        [void]$errors.Add('statusLogSeconds must be a number between 0 and 3600.')
    }

    if ($Config['provider'] -notin @('auto', 'acer-wmi', 'nitrosense')) {
        [void]$errors.Add("provider must be one of: auto, acer-wmi, nitrosense.")
    }

    if ($Config['logLevel'] -notin @('debug', 'info', 'warn', 'error')) {
        [void]$errors.Add('logLevel must be one of: debug, info, warn, error.')
    }

    if ($Config['pauseOnTurboMode'] -isnot [bool]) {
        [void]$errors.Add('pauseOnTurboMode must be true or false.')
    }

    if ($Config['fans'] -isnot [hashtable]) {
        [void]$errors.Add('fans must be an object with cpu and gpu entries.')
    }
    else {
        $enabledFans = 0
        foreach ($fanName in @('cpu', 'gpu')) {
            $fanId = $Config['fans'][$fanName]
            if ($null -eq $fanId) {
                continue
            }
            if (-not (Test-FanCurveNumber $fanId) -or [int]$fanId -lt 0 -or [int]$fanId -gt 255) {
                [void]$errors.Add("fans.$fanName must be null or a number between 0 and 255.")
            }
            else {
                $enabledFans++
            }
        }
        if ($enabledFans -eq 0) {
            [void]$errors.Add('At least one fan must be enabled.')
        }
    }

    foreach ($fanName in @('cpu', 'gpu')) {
        $fan = $Config[$fanName]
        if ($fan -isnot [hashtable]) {
            [void]$errors.Add("$fanName must be an object.")
            continue
        }

        $points = @($fan['curve'])
        if ($points.Count -lt 2) {
            [void]$errors.Add("$fanName.curve must contain at least two points.")
        }
        else {
            $lastTemp = $null
            $lastPercent = $null
            for ($index = 0; $index -lt $points.Count; $index++) {
                $point = $points[$index]
                if ($point -isnot [hashtable]) {
                    [void]$errors.Add("$fanName.curve[$index] must be an object.")
                    continue
                }
                if (-not (Test-FanCurveNumber $point['temp']) -or
                    [double]$point['temp'] -lt 0 -or [double]$point['temp'] -gt 120) {
                    [void]$errors.Add("$fanName.curve[$index].temp must be between 0 and 120.")
                }
                if (-not (Test-FanCurveNumber $point['percent']) -or
                    [double]$point['percent'] -lt 0 -or [double]$point['percent'] -gt 100) {
                    [void]$errors.Add("$fanName.curve[$index].percent must be between 0 and 100.")
                }
                if ((Test-FanCurveNumber $point['temp']) -and (Test-FanCurveNumber $point['percent'])) {
                    $temp = [double]$point['temp']
                    $percent = [double]$point['percent']
                    if ($null -ne $lastTemp -and $temp -le $lastTemp) {
                        [void]$errors.Add("$fanName.curve temperatures must be strictly increasing.")
                    }
                    if ($null -ne $lastPercent -and $percent -lt $lastPercent) {
                        [void]$errors.Add("$fanName.curve percentages must not decrease as temperature rises.")
                    }
                    $lastTemp = $temp
                    $lastPercent = $percent
                }
            }
        }

        if (-not (Test-FanCurveNumber $fan['smoothing']) -or
            [double]$fan['smoothing'] -lt 0.01 -or [double]$fan['smoothing'] -gt 1.0) {
            [void]$errors.Add("$fanName.smoothing must be between 0.01 and 1.0.")
        }
        if (-not (Test-FanCurveNumber $fan['maxStepUp']) -or
            [double]$fan['maxStepUp'] -lt 1 -or [double]$fan['maxStepUp'] -gt 100) {
            [void]$errors.Add("$fanName.maxStepUp must be between 1 and 100.")
        }
        if (-not (Test-FanCurveNumber $fan['maxStepDown']) -or
            [double]$fan['maxStepDown'] -lt 1 -or [double]$fan['maxStepDown'] -gt 100) {
            [void]$errors.Add("$fanName.maxStepDown must be between 1 and 100.")
        }
        if (-not (Test-FanCurveNumber $fan['emergencyTemp']) -or
            [double]$fan['emergencyTemp'] -lt 0 -or [double]$fan['emergencyTemp'] -gt 120) {
            [void]$errors.Add("$fanName.emergencyTemp must be between 0 and 120.")
        }

        if ($fan.ContainsKey('hysteresis') -and $null -ne $fan['hysteresis']) {
            $hysteresis = $fan['hysteresis']
            if ($hysteresis -isnot [hashtable]) {
                [void]$errors.Add("$fanName.hysteresis must be an object.")
            }
            else {
                $enterValid = (Test-FanCurveNumber $hysteresis['enter']) -and
                    [double]$hysteresis['enter'] -ge 0 -and [double]$hysteresis['enter'] -le 120
                $exitValid = (Test-FanCurveNumber $hysteresis['exit']) -and
                    [double]$hysteresis['exit'] -ge 0 -and [double]$hysteresis['exit'] -le 120
                if (-not $enterValid) {
                    [void]$errors.Add("$fanName.hysteresis.enter must be between 0 and 120.")
                }
                if (-not $exitValid) {
                    [void]$errors.Add("$fanName.hysteresis.exit must be between 0 and 120.")
                }
                if ($enterValid -and $exitValid -and [double]$hysteresis['enter'] -le [double]$hysteresis['exit']) {
                    [void]$errors.Add("$fanName.hysteresis.enter must be greater than exit.")
                }
                if (-not (Test-FanCurveNumber $hysteresis['lowPercent']) -or
                    [double]$hysteresis['lowPercent'] -lt 0 -or [double]$hysteresis['lowPercent'] -gt 100) {
                    [void]$errors.Add("$fanName.hysteresis.lowPercent must be between 0 and 100.")
                }
            }
        }
    }

    if ($Config['safety'] -isnot [hashtable]) {
        [void]$errors.Add('safety must be an object.')
    }
    else {
        $safety = $Config['safety']
        foreach ($key in @('minPercent', 'maxPercent', 'fallbackPercent')) {
            if (-not (Test-FanCurveNumber $safety[$key]) -or
                [double]$safety[$key] -lt 0 -or [double]$safety[$key] -gt 100) {
                [void]$errors.Add("safety.$key must be between 0 and 100.")
            }
        }
        if ((Test-FanCurveNumber $safety['minPercent']) -and
            (Test-FanCurveNumber $safety['maxPercent']) -and
            [double]$safety['minPercent'] -gt [double]$safety['maxPercent']) {
            [void]$errors.Add('safety.minPercent must not be greater than safety.maxPercent.')
        }
        if (-not (Test-FanCurveNumber $safety['failureThreshold']) -or
            [double]$safety['failureThreshold'] -lt 1 -or [double]$safety['failureThreshold'] -gt 60) {
            [void]$errors.Add('safety.failureThreshold must be between 1 and 60.')
        }
        if ($safety['restoreAutoOnExit'] -isnot [bool]) {
            [void]$errors.Add('safety.restoreAutoOnExit must be true or false.')
        }
    }

    return [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Errors = $errors.ToArray()
    }
}

function Assert-FanCurveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        [string]$Path
    )

    $result = Test-FanCurveConfig -Config $Config
    if (-not $result.Valid) {
        if ($Path) {
            $prefix = "Invalid FanCurve config '$Path':"
        }
        else {
            $prefix = 'Invalid FanCurve config:'
        }
        $details = ($result.Errors | ForEach-Object { " - $_" }) -join [Environment]::NewLine
        throw ($prefix + [Environment]::NewLine + $details)
    }
}

function Import-FanCurveConfig {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    $config = Get-FanCurveDefaultConfig

    if (-not $Path) {
        return $config
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "FanCurve config '$Path' was not found."
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'The file is empty.'
        }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read FanCurve config '$Path': $($_.Exception.Message)"
    }

    $override = ConvertTo-FanCurveHashtable -InputObject $parsed
    if ($override -isnot [hashtable]) {
        throw "FanCurve config '$Path' must contain a JSON object at the root."
    }

    $config = Merge-FanCurveConfig -Base $config -Override $override
    Assert-FanCurveConfig -Config $config -Path $Path
    return $config
}

#endregion

#region Curve math and WMI encoding

function Get-FanCurveTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Temperature,
        [Parameter(Mandatory)]
        $Points
    )

    $pointsArray = @($Points)
    if ($pointsArray.Count -lt 2) {
        throw 'A fan curve needs at least two points.'
    }

    $first = $pointsArray[0]
    $last = $pointsArray[$pointsArray.Count - 1]

    if ($Temperature -le [double]$first['temp']) {
        return [int][Math]::Round([double]$first['percent'])
    }
    if ($Temperature -ge [double]$last['temp']) {
        return [int][Math]::Round([double]$last['percent'])
    }

    for ($index = 0; $index -lt $pointsArray.Count - 1; $index++) {
        $left = $pointsArray[$index]
        $right = $pointsArray[$index + 1]
        $leftTemp = [double]$left['temp']
        $rightTemp = [double]$right['temp']

        if ($Temperature -ge $leftTemp -and $Temperature -le $rightTemp) {
            $span = $rightTemp - $leftTemp
            if ($span -le 0) {
                return [int][Math]::Round([double]$right['percent'])
            }
            $ratio = ($Temperature - $leftTemp) / $span
            $value = [double]$left['percent'] + ($ratio * ([double]$right['percent'] - [double]$left['percent']))
            $value = [Math]::Max(0, [Math]::Min(100, $value))
            return [int][Math]::Round($value)
        }
    }

    return [int][Math]::Round([double]$last['percent'])
}

function Get-FanCurveSteppedSpeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Current,
        [Parameter(Mandatory)]
        [int]$Target,
        [Parameter(Mandatory)]
        [double]$Temperature,
        [Parameter(Mandatory)]
        [double]$EmergencyTemp,
        [Parameter(Mandatory)]
        [int]$MaxStepUp,
        [Parameter(Mandatory)]
        [int]$MaxStepDown
    )

    $Current = [Math]::Max(0, [Math]::Min(100, $Current))
    $Target = [Math]::Max(0, [Math]::Min(100, $Target))

    if ($Temperature -ge $EmergencyTemp) {
        return $Target
    }
    if ($Target -gt $Current) {
        return [Math]::Min($Target, $Current + $MaxStepUp)
    }
    if ($Target -lt $Current) {
        return [Math]::Max($Target, $Current - $MaxStepDown)
    }
    return $Current
}

function Get-FanCurveHysteresisState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$CurrentState,
        [Parameter(Mandatory)]
        [double]$Temperature,
        [Parameter(Mandatory)]
        [double]$Enter,
        [Parameter(Mandatory)]
        [double]$Exit
    )

    if ($Temperature -ge $Enter) {
        return $true
    }
    if ($Temperature -le $Exit) {
        return $false
    }
    return $CurrentState
}

function Get-FanSpeedInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$FanId,
        [Parameter(Mandatory)]
        [int]$Percent
    )

    $speed = [Math]::Max(0, [Math]::Min(100, $Percent))
    return [uint64](([uint64]($speed -band 0xFF) * 256) -bor [uint64]($FanId -band 0xFF))
}

function Get-FanBehaviorInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$FanBitmap,
        [Parameter(Mandatory)]
        [int]$CpuMode,
        [Parameter(Mandatory)]
        [int]$GpuMode
    )

    $value = [uint64]($FanBitmap -band 0xFFFF)
    if ($FanBitmap -band 0x1) {
        $value = $value -bor ([uint64]($CpuMode -band 0x3) * 65536)
    }
    if ($FanBitmap -band 0x8) {
        $value = $value -bor ([uint64]($GpuMode -band 0x3) * 4194304)
    }
    return $value
}

function Get-FanSysInfoValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uint64]$Raw
    )
    return [int](($Raw -shr 8) -band 0xFFFF)
}

function Get-FanBehaviorMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uint64]$Raw
    )
    return [pscustomobject]@{
        Status = [int]($Raw -band 0xFF)
        Cpu = [int](($Raw -shr 8) -band 0x3)
        Gpu = [int](($Raw -shr 14) -band 0x3)
    }
}

function Get-FanSpeedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uint64]$Raw
    )
    return [pscustomobject]@{
        Status = [int]($Raw -band 0xFF)
        Percent = [int](($Raw -shr 8) -band 0xFF)
    }
}

function Get-FanCurveBehaviorBitmap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $bitmap = 0
    if ($null -ne $Config['fans']['cpu']) {
        $bitmap = $bitmap -bor 0x1
    }
    if ($null -ne $Config['fans']['gpu']) {
        $bitmap = $bitmap -bor 0x8
    }
    return $bitmap
}

#endregion

#region Acer WMI

function Test-FanCurveAdmin {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AcerGamingInstance {
    [CmdletBinding()]
    param()

    try {
        $instance = Get-CimInstance -Namespace 'root\wmi' -ClassName 'AcerGamingFunction' -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        if ($_.Exception.Message -match 'Access denied|Access is denied') {
            throw 'Access denied reading AcerGamingFunction. Run FanCurve from an elevated PowerShell window.'
        }
        throw "AcerGamingFunction is not available: $($_.Exception.Message)"
    }

    if (-not $instance) {
        throw 'AcerGamingFunction was not found. This machine does not expose Acer''s gaming WMI interface.'
    }

    return $instance
}

function Invoke-AcerGamingMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [Parameter(Mandatory)]
        [string]$MethodName,
        [Parameter(Mandatory)]
        [uint64]$InputValue,
        [ValidateSet('UInt32', 'UInt64')]
        [string]$InputType = 'UInt64'
    )

    if ($InputType -eq 'UInt32') {
        $methodInput = [uint32]$InputValue
    }
    else {
        $methodInput = [uint64]$InputValue
    }

    try {
        $result = Invoke-CimMethod -InputObject $Instance -MethodName $MethodName -Arguments @{
            gmInput = $methodInput
        } -ErrorAction Stop
    }
    catch {
        throw "WMI $MethodName failed: $($_.Exception.Message)"
    }

    if ($null -eq $result -or $null -eq $result.gmOutput) {
        throw "WMI $MethodName returned no output."
    }

    return [uint64]$result.gmOutput
}

function Get-AcerGamingSysInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [Parameter(Mandatory)]
        [ValidateSet('SupportedSensors', 'BatteryStatus', 'CpuTemperature', 'CpuFanRpm', 'SystemTemperature', 'GpuFanRpm', 'GpuTemperature')]
        [string]$Sensor
    )

    $sensorInputs = @{
        SupportedSensors = 0x0000
        BatteryStatus = 0x0002
        CpuTemperature = 0x0101
        CpuFanRpm = 0x0201
        SystemTemperature = 0x0301
        GpuFanRpm = 0x0601
        GpuTemperature = 0x0A01
    }

    $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'GetGamingSysInfo' `
        -InputValue ([uint64]$sensorInputs[$Sensor]) -InputType UInt32

    return [pscustomobject]@{
        Sensor = $Sensor
        Raw = $raw
        Status = [int]($raw -band 0xFF)
        Value = Get-FanSysInfoValue -Raw $raw
    }
}

function Get-AcerSupportedSensor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Instance
    )

    $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'GetGamingSysInfo' -InputValue 0 -InputType UInt32
    return [int](($raw -shr 24) -band 0xFFFF)
}

function Get-AcerFanMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [int]$FanBitmap = 9
    )

    $bitmaps = @($FanBitmap)
    if ($FanBitmap -eq 9) {
        $bitmaps += 1
        $bitmaps += 8
    }

    $lastError = $null
    foreach ($bitmap in $bitmaps) {
        try {
            $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'GetGamingFanBehavior' `
                -InputValue ([uint64]$bitmap) -InputType UInt32
            $mode = Get-FanBehaviorMode -Raw $raw
            if ($mode.Status -eq 0) {
                return $mode
            }
            $lastError = "GetGamingFanBehavior returned status $($mode.Status) for fan bitmap $bitmap."
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }

    throw $lastError
}

function Set-AcerFanMode {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [Parameter(Mandatory)]
        [int]$FanBitmap,
        [Parameter(Mandatory)]
        [int]$CpuMode,
        [Parameter(Mandatory)]
        [int]$GpuMode
    )

    if (-not $PSCmdlet.ShouldProcess("fan bitmap 0x$($FanBitmap.ToString('X'))", "Set CPU mode $CpuMode and GPU mode $GpuMode")) {
        return 0
    }

    $inputValue = Get-FanBehaviorInput -FanBitmap $FanBitmap -CpuMode $CpuMode -GpuMode $GpuMode
    $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'SetGamingFanBehavior' `
        -InputValue $inputValue -InputType UInt64
    $status = [int]($raw -band 0xFF)
    if ($status -ne 0) {
        throw ('SetGamingFanBehavior failed with status {0} (input 0x{1:X}).' -f $status, $inputValue)
    }
    return $status
}

function Get-AcerFanSpeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [Parameter(Mandatory)]
        [int]$FanId
    )

    $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'GetGamingFanSpeed' `
        -InputValue ([uint64]$FanId) -InputType UInt32
    $speed = Get-FanSpeedValue -Raw $raw
    if ($speed.Status -ne 0) {
        throw "GetGamingFanSpeed($FanId) returned status $($speed.Status)."
    }
    return $speed
}

function Set-AcerFanSpeed {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        $Instance,
        [Parameter(Mandatory)]
        [int]$FanId,
        [Parameter(Mandatory)]
        [int]$Percent
    )

    if (-not $PSCmdlet.ShouldProcess("fan $FanId", "Set speed to $Percent%")) {
        return $Percent
    }

    $speed = [Math]::Max(0, [Math]::Min(100, $Percent))
    $inputValue = Get-FanSpeedInput -FanId $FanId -Percent $speed
    $raw = Invoke-AcerGamingMethod -Instance $Instance -MethodName 'SetGamingFanSpeed' `
        -InputValue $inputValue -InputType UInt64
    $status = [int]($raw -band 0xFF)
    if ($status -ne 0) {
        throw "SetGamingFanSpeed(fan $FanId, $speed%) failed with status $status."
    }
    return $speed
}

function Restore-AcerFanAuto {
    [CmdletBinding()]
    param(
        $Instance,
        [int]$FanBitmap = 9,
        [switch]$Console
    )

    if (-not $Instance) {
        $Instance = Get-AcerGamingInstance
    }

    try {
        Set-AcerFanMode -Instance $Instance -FanBitmap $FanBitmap -CpuMode 1 -GpuMode 1
    }
    catch {
        if ($FanBitmap -eq 9) {
            Set-AcerFanMode -Instance $Instance -FanBitmap 1 -CpuMode 1 -GpuMode 1
        }
        else {
            throw
        }
    }

    Write-FanCurveLog -Level info -Message 'Fans restored to AUTO.' -Console:$Console
}

function Get-AcerSystemInfo {
    [CmdletBinding()]
    param()

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name })

    $biosVersion = $null
    if ($bios) {
        if ($bios.SMBIOSBIOSVersion) {
            $biosVersion = $bios.SMBIOSBIOSVersion
        }
        else {
            $biosVersion = $bios.Version
        }
    }

    return [pscustomobject]@{
        Manufacturer = if ($computer) { $computer.Manufacturer } else { $null }
        Model = if ($computer) { $computer.Model } else { $null }
        BiosVersion = $biosVersion
        Cpu = if ($processor) { $processor.Name } else { $null }
        Gpus = $gpus
    }
}

#endregion

#region Temperature providers

function Get-NitroSenseTemperature {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    }
    catch {
        throw "Windows UI Automation is not available: $($_.Exception.Message)"
    }

    $process = Get-Process -Name 'NitroSense' -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $process) {
        throw 'NitroSense is not running, or its window is not available.'
    }

    $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$process.MainWindowHandle)
    if (-not $root) {
        throw 'Could not attach to the NitroSense window.'
    }

    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)

    $texts = New-Object System.Collections.ArrayList
    foreach ($element in $elements) {
        if ($element.Current.ControlType.ProgrammaticName -eq 'ControlType.Text') {
            [void]$texts.Add([string]$element.Current.Name)
        }
    }

    $findValue = {
        param([string]$Label)

        for ($index = 0; $index -lt $texts.Count; $index++) {
            if ($texts[$index] -notmatch '^(CPU|GPU)\b') {
                continue
            }
            if ($Matches[1] -ne $Label) {
                continue
            }

            $limit = [Math]::Min($index + 5, $texts.Count - 1)
            for ($lookAhead = $index + 1; $lookAhead -le $limit; $lookAhead++) {
                $candidate = [string]$texts[$lookAhead]
                if ($candidate -match '^(CPU|GPU)\b') {
                    break
                }
                if ($candidate -match 'RPM') {
                    break
                }
                if ($candidate -match '^\s*(\d{1,3})\s*(?:\D.*)?$') {
                    $value = [int]$Matches[1]
                    if ($value -lt 1 -or $value -gt 120) {
                        continue
                    }
                    $next = ''
                    if ($lookAhead + 1 -lt $texts.Count) {
                        $next = [string]$texts[$lookAhead + 1]
                    }
                    if ($next -match '^\s*%' -or $next -match 'RPM') {
                        continue
                    }
                    return $value
                }
            }
        }

        return $null
    }

    $cpu = & $findValue 'CPU'
    $gpu = & $findValue 'GPU'

    if ($null -eq $cpu -and $null -eq $gpu) {
        throw 'No CPU or GPU temperature values were found in the NitroSense window.'
    }

    $fanRpms = @()
    for ($index = 0; $index -lt $texts.Count - 1; $index++) {
        if ($texts[$index] -match '^\s*(\d{3,5})\s*$') {
            $rpmCandidate = [int]$Matches[1]
            if ($texts[$index + 1] -match '^RPM') {
                $fanRpms += $rpmCandidate
            }
        }
    }

    $cpuFanRpm = $null
    $gpuFanRpm = $null
    if ($fanRpms.Count -ge 2) {
        $cpuFanRpm = $fanRpms[0]
        $gpuFanRpm = $fanRpms[1]
    }

    $gpuEstimated = $false
    if ($null -eq $gpu) {
        $gpu = $cpu
        $gpuEstimated = $true
    }

    return [pscustomobject]@{
        Cpu = [int]$cpu
        Gpu = [int]$gpu
        GpuEstimated = $gpuEstimated
        CpuFanRpm = $cpuFanRpm
        GpuFanRpm = $gpuFanRpm
        Source = 'nitrosense'
        Timestamp = Get-Date
    }
}

function Get-FanCurveTemperature {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'acer-wmi', 'nitrosense')]
        [string]$Provider = 'auto',
        $AcerInstance
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if ($Provider -in @('auto', 'acer-wmi')) {
        try {
            if (-not $AcerInstance) {
                $AcerInstance = Get-AcerGamingInstance
            }

            $cpu = Get-AcerGamingSysInfo -Instance $AcerInstance -Sensor CpuTemperature
            if ($cpu.Status -ne 0 -or $cpu.Value -lt 1 -or $cpu.Value -gt 120) {
                throw "CPU temperature is unavailable (status $($cpu.Status), value $($cpu.Value))."
            }

            $gpu = Get-AcerGamingSysInfo -Instance $AcerInstance -Sensor GpuTemperature
            $gpuValue = $null
            if ($gpu.Status -eq 0 -and $gpu.Value -ge 1 -and $gpu.Value -le 120) {
                $gpuValue = [int]$gpu.Value
            }

            $cpuFan = Get-AcerGamingSysInfo -Instance $AcerInstance -Sensor CpuFanRpm
            $gpuFan = Get-AcerGamingSysInfo -Instance $AcerInstance -Sensor GpuFanRpm

            $cpuFanRpm = $null
            if ($cpuFan.Status -eq 0 -and $cpuFan.Value -ge 1 -and $cpuFan.Value -le 10000) {
                $cpuFanRpm = [int]$cpuFan.Value
            }
            $gpuFanRpm = $null
            if ($gpuFan.Status -eq 0 -and $gpuFan.Value -ge 1 -and $gpuFan.Value -le 10000) {
                $gpuFanRpm = [int]$gpuFan.Value
            }

            $gpuEstimated = $false
            if ($null -eq $gpuValue) {
                $gpuValue = [int]$cpu.Value
                $gpuEstimated = $true
            }

            return [pscustomobject]@{
                Cpu = [int]$cpu.Value
                Gpu = [int]$gpuValue
                GpuEstimated = $gpuEstimated
                CpuFanRpm = $cpuFanRpm
                GpuFanRpm = $gpuFanRpm
                Source = 'acer-wmi'
                Timestamp = Get-Date
            }
        }
        catch {
            [void]$errors.Add("acer-wmi: $($_.Exception.Message)")
            if ($Provider -eq 'acer-wmi') {
                throw "The acer-wmi temperature provider failed. $($_.Exception.Message)"
            }
        }
    }

    if ($Provider -in @('auto', 'nitrosense')) {
        try {
            return Get-NitroSenseTemperature
        }
        catch {
            [void]$errors.Add("nitrosense: $($_.Exception.Message)")
        }
    }

    throw ("No temperature provider is available. " + ($errors -join ' | '))
}

#endregion

#region Controller

function Start-FanCurveController {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [hashtable]$Config,
        [string]$ConfigPath,
        [string]$LogPath,
        [ValidateSet('debug', 'info', 'warn', 'error')]
        [string]$LogLevel,
        [switch]$DryRun,
        [switch]$Once,
        [switch]$NoRestore
    )

    if (-not $PSCmdlet.ShouldProcess('FanCurve controller', 'Start')) {
        return
    }

    if (-not $Config) {
        $Config = Import-FanCurveConfig -Path $ConfigPath
    }

    if (-not $LogLevel) {
        $LogLevel = $Config['logLevel']
    }

    Initialize-FanCurveLog -Path $LogPath -Level $LogLevel

    if (-not $DryRun -and -not (Test-FanCurveAdmin)) {
        throw 'FanCurve must run elevated to write fan speeds. Right-click PowerShell and choose "Run as administrator".'
    }

    $mutex = New-Object System.Threading.Mutex($false, 'Local\FanCurveController')
    if (-not $mutex.WaitOne(0)) {
        $mutex.Dispose()
        throw 'Another FanCurve controller is already running in this session.'
    }

    $instance = $null
    $bitmap = Get-FanCurveBehaviorBitmap -Config $Config
    $cpuControlled = $null -ne $Config['fans']['cpu']
    $gpuControlled = $null -ne $Config['fans']['gpu']
    $paused = $false
    $lastModeApply = [datetime]::MinValue
    $lastLog = [datetime]::MinValue
    $lastCpuApplied = -1
    $lastGpuApplied = -1
    $cpuCurrent = 0
    $gpuCurrent = 0
    $cpuSmooth = $null
    $gpuSmooth = $null
    $gpuHigh = $false
    $tempFailures = 0
    $writeFailures = 0
    $gpuEstimateLogged = $false

    try {
        $system = Get-AcerSystemInfo
        $model = if ($system.Model) { "$($system.Manufacturer) $($system.Model)" } else { 'unknown model' }
        Write-FanCurveLog -Level info -Message ("FanCurve {0} starting on {1}" -f $script:FanCurveVersion, $model) -Console
        Write-FanCurveLog -Level info -Message ("Config: {0}" -f $(if ($ConfigPath) { $ConfigPath } else { 'built-in defaults' })) -Console
        Write-FanCurveLog -Level info -Message ("Provider: {0}; poll: {1}s; fans: bitmap 0x{2:X}" -f $Config['provider'], $Config['pollSeconds'], $bitmap) -Console

        if (-not $DryRun) {
            $instance = Get-AcerGamingInstance

            try {
                $mode = Get-AcerFanMode -Instance $instance -FanBitmap $bitmap
                if ($Config['pauseOnTurboMode'] -and $mode.Cpu -eq 2) {
                    $paused = $true
                    Write-FanCurveLog -Level info -Message 'Acer firmware is in Turbo/Max mode. FanCurve will wait until another mode is selected.' -Console
                }
                else {
                    Set-AcerFanMode -Instance $instance -FanBitmap $bitmap -CpuMode 3 -GpuMode 3
                    $lastModeApply = Get-Date
                    Write-FanCurveLog -Level info -Message 'Custom fan mode enabled.' -Console
                }
            }
            catch {
                Write-FanCurveLog -Level warn -Message "Could not read or set the initial fan mode: $($_.Exception.Message)" -Console
                if ($bitmap -eq 9) {
                    try {
                        Set-AcerFanMode -Instance $instance -FanBitmap 1 -CpuMode 3 -GpuMode 1
                        $bitmap = 1
                        $gpuControlled = $false
                        $lastModeApply = Get-Date
                        Write-FanCurveLog -Level warn -Message 'The Acer firmware rejected a two-fan custom mode. Continuing with CPU fan control only.' -Console
                    }
                    catch {
                        throw "Could not enable custom fan mode: $($_.Exception.Message)"
                    }
                }
                else {
                    throw "Could not enable custom fan mode: $($_.Exception.Message)"
                }
            }
        }

        while ($true) {
            $cycleStarted = Get-Date

            try {
                $temperatures = Get-FanCurveTemperature -Provider $Config['provider'] -AcerInstance $instance
                $tempFailures = 0
            }
            catch {
                $tempFailures++
                Write-FanCurveLog -Level warn -Message ("Temperature read failed ({0}/{1}): {2}" -f $tempFailures, $Config['safety']['failureThreshold'], $_.Exception.Message) -Console

                if ($tempFailures -ge [int]$Config['safety']['failureThreshold'] -and -not $DryRun) {
                    try {
                        if ($null -eq $instance) {
                            $instance = Get-AcerGamingInstance
                        }
                        $fallback = [Math]::Max([int]$Config['safety']['minPercent'],
                            [Math]::Min([int]$Config['safety']['maxPercent'], [int]$Config['safety']['fallbackPercent']))
                        if ($cpuControlled) {
                            [void](Set-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['cpu']) -Percent $fallback)
                        }
                        if ($gpuControlled) {
                            [void](Set-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['gpu']) -Percent $fallback)
                        }
                        Write-FanCurveLog -Level warn -Message ("Fallback applied: both fans at {0}%." -f $fallback) -Console
                    }
                    catch {
                        Write-FanCurveLog -Level error -Message "Fallback fan write failed: $($_.Exception.Message)" -Console
                    }
                }

                if ($Once) {
                    break
                }
                Start-Sleep -Seconds ([int]$Config['pollSeconds'])
                continue
            }

            if ($temperatures.GpuEstimated -and -not $gpuEstimateLogged) {
                Write-FanCurveLog -Level warn -Message 'GPU temperature is unavailable; the GPU fan will follow CPU temperature.' -Console
                $gpuEstimateLogged = $true
            }

            if (-not $DryRun -and $Config['pauseOnTurboMode']) {
                try {
                    $mode = Get-AcerFanMode -Instance $instance -FanBitmap $bitmap
                    if ($mode.Cpu -eq 2) {
                        if (-not $paused) {
                            Write-FanCurveLog -Level info -Message 'Turbo/Max mode detected. Controller paused.' -Console
                            $paused = $true
                            $cpuCurrent = 0
                            $gpuCurrent = 0
                            $cpuSmooth = $null
                            $gpuSmooth = $null
                            $gpuHigh = $false
                            $lastCpuApplied = -1
                            $lastGpuApplied = -1
                        }
                        if ($Once) {
                            break
                        }
                        Start-Sleep -Seconds ([int]$Config['pollSeconds'])
                        continue
                    }
                    if ($paused) {
                        Write-FanCurveLog -Level info -Message 'Firmware is no longer in Turbo/Max mode. Controller resuming.' -Console
                        $paused = $false
                        $cpuCurrent = 0
                        $gpuCurrent = 0
                        $cpuSmooth = $null
                        $gpuSmooth = $null
                        $gpuHigh = $false
                    }
                }
                catch {
                    Write-FanCurveLog -Level debug -Message "Could not read fan mode: $($_.Exception.Message)"
                }
            }

            $cpuTemp = [double]$temperatures.Cpu
            $gpuTemp = [double]$temperatures.Gpu

            $cpuAlpha = [double]$Config['cpu']['smoothing']
            if ($null -eq $cpuSmooth) {
                $cpuSmooth = $cpuTemp
            }
            else {
                $cpuSmooth = ($cpuAlpha * $cpuTemp) + ((1.0 - $cpuAlpha) * $cpuSmooth)
            }

            $cpuTarget = Get-FanCurveTarget -Temperature $cpuSmooth -Points $Config['cpu']['curve']
            if ($cpuTemp -ge [double]$Config['cpu']['emergencyTemp']) {
                $cpuTarget = [int]$Config['safety']['maxPercent']
                $cpuSmooth = $cpuTemp
            }

            $gpuAlpha = [double]$Config['gpu']['smoothing']
            if ($null -eq $gpuSmooth) {
                $gpuSmooth = $gpuTemp
            }
            else {
                $gpuSmooth = ($gpuAlpha * $gpuTemp) + ((1.0 - $gpuAlpha) * $gpuSmooth)
            }

            if ($Config['gpu'].ContainsKey('hysteresis') -and $null -ne $Config['gpu']['hysteresis']) {
                $hysteresis = $Config['gpu']['hysteresis']
                $gpuHigh = Get-FanCurveHysteresisState -CurrentState $gpuHigh -Temperature $gpuTemp `
                    -Enter ([double]$hysteresis['enter']) -Exit ([double]$hysteresis['exit'])
                if ($gpuHigh) {
                    $gpuTarget = Get-FanCurveTarget -Temperature $gpuSmooth -Points $Config['gpu']['curve']
                }
                else {
                    $gpuTarget = [int]$hysteresis['lowPercent']
                }
            }
            else {
                $gpuTarget = Get-FanCurveTarget -Temperature $gpuSmooth -Points $Config['gpu']['curve']
            }

            if ($gpuTemp -ge [double]$Config['gpu']['emergencyTemp']) {
                $gpuTarget = [int]$Config['safety']['maxPercent']
                $gpuSmooth = $gpuTemp
            }

            $cpuTarget = [Math]::Max([int]$Config['safety']['minPercent'],
                [Math]::Min([int]$Config['safety']['maxPercent'], $cpuTarget))
            $gpuTarget = [Math]::Max([int]$Config['safety']['minPercent'],
                [Math]::Min([int]$Config['safety']['maxPercent'], $gpuTarget))

            if ($cpuCurrent -le 0) {
                if (-not $DryRun -and $cpuControlled) {
                    try {
                        $readBack = Get-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['cpu'])
                        if ($readBack.Percent -gt 0) {
                            $cpuCurrent = [int]$readBack.Percent
                        }
                        else {
                            $cpuCurrent = $cpuTarget
                        }
                    }
                    catch {
                        $cpuCurrent = $cpuTarget
                    }
                }
                else {
                    $cpuCurrent = $cpuTarget
                }
            }

            if ($gpuCurrent -le 0) {
                if (-not $DryRun -and $gpuControlled) {
                    try {
                        $readBack = Get-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['gpu'])
                        if ($readBack.Percent -gt 0) {
                            $gpuCurrent = [int]$readBack.Percent
                        }
                        else {
                            $gpuCurrent = $gpuTarget
                        }
                    }
                    catch {
                        $gpuCurrent = $gpuTarget
                    }
                }
                else {
                    $gpuCurrent = $gpuTarget
                }
            }

            $cpuCurrent = Get-FanCurveSteppedSpeed -Current $cpuCurrent -Target $cpuTarget `
                -Temperature $cpuTemp -EmergencyTemp ([double]$Config['cpu']['emergencyTemp']) `
                -MaxStepUp ([int]$Config['cpu']['maxStepUp']) -MaxStepDown ([int]$Config['cpu']['maxStepDown'])
            $gpuCurrent = Get-FanCurveSteppedSpeed -Current $gpuCurrent -Target $gpuTarget `
                -Temperature $gpuTemp -EmergencyTemp ([double]$Config['gpu']['emergencyTemp']) `
                -MaxStepUp ([int]$Config['gpu']['maxStepUp']) -MaxStepDown ([int]$Config['gpu']['maxStepDown'])

            if (-not $DryRun) {
                if (((Get-Date) - $lastModeApply).TotalSeconds -ge [double]$Config['modeRefreshSeconds']) {
                    try {
                        Set-AcerFanMode -Instance $instance -FanBitmap $bitmap -CpuMode 3 -GpuMode 3
                        $lastModeApply = Get-Date
                    }
                    catch {
                        Write-FanCurveLog -Level warn -Message "Could not re-apply custom fan mode: $($_.Exception.Message)" -Console
                    }
                }

                $cycleWriteFailed = $false
                if ($cpuControlled) {
                    try {
                        [void](Set-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['cpu']) -Percent $cpuCurrent)
                    }
                    catch {
                        $cycleWriteFailed = $true
                        Write-FanCurveLog -Level error -Message "CPU fan write failed: $($_.Exception.Message)" -Console
                    }
                }
                if ($gpuControlled) {
                    try {
                        [void](Set-AcerFanSpeed -Instance $instance -FanId ([int]$Config['fans']['gpu']) -Percent $gpuCurrent)
                    }
                    catch {
                        $cycleWriteFailed = $true
                        Write-FanCurveLog -Level error -Message "GPU fan write failed: $($_.Exception.Message)" -Console
                    }
                }

                if ($cycleWriteFailed) {
                    $writeFailures++
                    if ($writeFailures -ge 3) {
                        throw 'Fan writes failed three cycles in a row. Restoring AUTO and stopping.'
                    }
                }
                else {
                    $writeFailures = 0
                }
            }

            $changed = ($cpuCurrent -ne $lastCpuApplied) -or ($gpuCurrent -ne $lastGpuApplied)
            $heartbeat = $Config['statusLogSeconds'] -gt 0 -and
                ((Get-Date) - $lastLog).TotalSeconds -ge [double]$Config['statusLogSeconds']

            if ($changed -or $heartbeat) {
                $hasGpuHysteresis = $Config['gpu'].ContainsKey('hysteresis') -and $null -ne $Config['gpu']['hysteresis']
                $gpuModeText = if ($gpuHigh) { 'high' } elseif ($hasGpuHysteresis) { 'quiet' } else { 'curve' }
                $estimated = if ($temperatures.GpuEstimated) { ' (estimated)' } else { '' }
                $rpm = ''
                if ($null -ne $temperatures.CpuFanRpm -or $null -ne $temperatures.GpuFanRpm) {
                    $rpm = '  rpm=' + $temperatures.CpuFanRpm + '/' + $temperatures.GpuFanRpm
                }
                $message = 'cpu={0}C/{1:N1}->{2}% applied={3}%  gpu={4}C{5} {6}->{7}% applied={8}%  [{9}]{10}' -f `
                    $temperatures.Cpu, $cpuSmooth, $cpuTarget, $cpuCurrent,
                    $temperatures.Gpu, $estimated, $gpuModeText, $gpuTarget, $gpuCurrent,
                    $temperatures.Source, $rpm
                Write-FanCurveLog -Level info -Message $message -Console
                $lastCpuApplied = $cpuCurrent
                $lastGpuApplied = $gpuCurrent
                $lastLog = Get-Date
            }

            if ($Once) {
                break
            }

            $elapsed = ((Get-Date) - $cycleStarted).TotalSeconds
            $sleepSeconds = [Math]::Max(1, [double]$Config['pollSeconds'] - $elapsed)
            Start-Sleep -Seconds ([int][Math]::Ceiling($sleepSeconds))
        }
    }
    finally {
        if (-not $DryRun -and -not $NoRestore -and $Config['safety']['restoreAutoOnExit']) {
            try {
                if (-not $instance) {
                    $instance = Get-AcerGamingInstance
                }
                Restore-AcerFanAuto -Instance $instance -FanBitmap 9 -Console
            }
            catch {
                Write-FanCurveLog -Level error -Message "Could not restore AUTO mode: $($_.Exception.Message)" -Console
            }
        }

        try {
            $mutex.ReleaseMutex()
        }
        catch {
            Write-Verbose "Controller mutex was already released: $($_.Exception.Message)"
        }
        $mutex.Dispose()
        Write-FanCurveLog -Level info -Message 'FanCurve stopped.' -Console
    }
}

#endregion

#region Status and diagnostics

function Get-FanCurveTaskStatus {
    [CmdletBinding()]
    param(
        [string]$TaskName = 'FanCurve'
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return [pscustomobject]@{
            Installed = $false
            State = 'Not installed'
            LastRunTime = $null
            LastTaskResult = $null
            LastTaskResultText = $null
        }
    }

    $info = $null
    try {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
    }
    catch {
        Write-Verbose "Scheduled task information is unavailable for '$TaskName': $($_.Exception.Message)"
    }

    $resultText = $null
    if ($info -and $null -ne $info.LastTaskResult) {
        $code = [int64]$info.LastTaskResult
        switch ($code) {
            0 { $resultText = 'Success' }
            267008 { $resultText = 'Ready' }
            267009 { $resultText = 'Running' }
            267011 { $resultText = 'Never run' }
            default { $resultText = ('0x{0:X}' -f $code) }
        }
    }

    return [pscustomobject]@{
        Installed = $true
        State = [string]$task.State
        LastRunTime = if ($info) { $info.LastRunTime } else { $null }
        LastTaskResult = if ($info) { $info.LastTaskResult } else { $null }
        LastTaskResultText = $resultText
    }
}

function Get-FanCurveStatus {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $config = Import-FanCurveConfig -Path $ConfigPath
    $system = Get-AcerSystemInfo
    $admin = Test-FanCurveAdmin
    $task = Get-FanCurveTaskStatus
    $errors = New-Object System.Collections.Generic.List[string]

    $mode = $null
    $cpuSpeed = $null
    $gpuSpeed = $null
    $temperatures = $null
    $instance = $null

    if ($admin) {
        try {
            $instance = Get-AcerGamingInstance
            try {
                $mode = Get-AcerFanMode -Instance $instance -FanBitmap (Get-FanCurveBehaviorBitmap -Config $config)
            }
            catch {
                [void]$errors.Add("Fan mode: $($_.Exception.Message)")
            }
            if ($null -ne $config['fans']['cpu']) {
                try {
                    $cpuSpeed = Get-AcerFanSpeed -Instance $instance -FanId ([int]$config['fans']['cpu'])
                }
                catch {
                    [void]$errors.Add("CPU fan speed: $($_.Exception.Message)")
                }
            }
            if ($null -ne $config['fans']['gpu']) {
                try {
                    $gpuSpeed = Get-AcerFanSpeed -Instance $instance -FanId ([int]$config['fans']['gpu'])
                }
                catch {
                    [void]$errors.Add("GPU fan speed: $($_.Exception.Message)")
                }
            }
        }
        catch {
            [void]$errors.Add($_.Exception.Message)
        }
    }
    else {
        [void]$errors.Add('Not elevated. Fan mode and fan speed readback require administrator rights.')
    }

    try {
        $temperatures = Get-FanCurveTemperature -Provider $config['provider'] -AcerInstance $instance
    }
    catch {
        [void]$errors.Add("Temperature: $($_.Exception.Message)")
    }

    return [pscustomobject]@{
        Version = $script:FanCurveVersion
        Model = if ($system.Model) { "$($system.Manufacturer) $($system.Model)" } else { 'Unknown' }
        BiosVersion = $system.BiosVersion
        Cpu = $system.Cpu
        Gpus = $system.Gpus
        Administrator = $admin
        ConfigPath = $ConfigPath
        Provider = $config['provider']
        Task = $task
        Mode = $mode
        CpuSpeed = $cpuSpeed
        GpuSpeed = $gpuSpeed
        Temperatures = $temperatures
        Errors = $errors.ToArray()
    }
}

function Format-FanCurveStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Status
    )

    Write-Output ("FanCurve {0}" -f $Status.Version)
    Write-Output ("Model:   {0}" -f $Status.Model)
    if ($Status.BiosVersion) {
        Write-Output ("BIOS:    {0}" -f $Status.BiosVersion)
    }
    Write-Output ("Admin:   {0}" -f $(if ($Status.Administrator) { 'yes' } else { 'no' }))
    Write-Output ("Config:  {0}" -f $(if ($Status.ConfigPath) { $Status.ConfigPath } else { 'built-in defaults' }))
    Write-Output ("Provider: {0}" -f $Status.Provider)

    if ($Status.Task.Installed) {
        Write-Output ("Task:    {0} ({1}, last result: {2})" -f $Status.Task.State, $Status.Task.LastTaskResultText, $Status.Task.LastTaskResult)
    }
    else {
        Write-Output 'Task:    not installed'
    }

    if ($Status.Mode) {
        Write-Output ("Mode:    CPU={0} GPU={1} (1=auto, 2=turbo, 3=custom)" -f $Status.Mode.Cpu, $Status.Mode.Gpu)
    }
    if ($Status.Temperatures) {
        $temps = $Status.Temperatures
        $gpuText = if ($temps.GpuEstimated) { "$($temps.Gpu) C (estimated)" } else { "$($temps.Gpu) C" }
        $rpm = ''
        if ($null -ne $temps.CpuFanRpm -or $null -ne $temps.GpuFanRpm) {
            $rpm = "  fan $($temps.CpuFanRpm) / $($temps.GpuFanRpm) RPM"
        }
        Write-Output ("CPU:     {0} C  {1}{2}" -f $temps.Cpu, $(if ($null -ne $Status.CpuSpeed) { "EC $($Status.CpuSpeed.Percent)%" } else { '' }), $rpm)
        Write-Output ("GPU:     {0}  {1}" -f $gpuText, $(if ($null -ne $Status.GpuSpeed) { "EC $($Status.GpuSpeed.Percent)%" } else { '' }))
    }

    if ($Status.Errors.Count -gt 0) {
        Write-Output ''
        Write-Output 'Notes:'
        foreach ($errorMessage in $Status.Errors) {
            Write-Output ("  - {0}" -f $errorMessage)
        }
    }
}

function Invoke-FanCurveDoctor {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $add = {
        param([string]$Name, [string]$State, [string]$Detail)
        [void]$checks.Add([pscustomobject]@{ Name = $Name; Status = $State; Detail = $Detail })
    }

    & $add 'PowerShell' 'ok' ("{0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
    & $add 'Operating system' 'ok' ([System.Environment]::OSVersion.VersionString)

    $admin = Test-FanCurveAdmin
    if ($admin) {
        & $add 'Administrator' 'ok' 'Elevated session'
    }
    else {
        & $add 'Administrator' 'warn' 'Not elevated. Run doctor from an elevated terminal for the full hardware probe.'
    }

    $system = Get-AcerSystemInfo
    if ($system.Manufacturer -match 'Acer|Gateway|Packard Bell') {
        & $add 'System' 'ok' ("{0} {1}" -f $system.Manufacturer, $system.Model)
    }
    elseif ($system.Model) {
        & $add 'System' 'warn' ("{0} {1} is not an Acer system; the Acer WMI interface may not exist." -f $system.Manufacturer, $system.Model)
    }

    if ($system.Cpu) {
        & $add 'CPU' 'ok' $system.Cpu
    }
    if ($system.Gpus.Count -gt 0) {
        & $add 'GPU' 'ok' ($system.Gpus -join '; ')
    }

    try {
        $class = Get-CimClass -Namespace 'root\wmi' -ClassName 'AcerGamingFunction' -ErrorAction Stop
        $methodNames = @($class.CimClassMethods | ForEach-Object { $_.Name })
        $required = @('GetGamingSysInfo', 'GetGamingFanBehavior', 'SetGamingFanBehavior', 'GetGamingFanSpeed', 'SetGamingFanSpeed')
        $missing = @($required | Where-Object { $methodNames -notcontains $_ })
        if ($missing.Count -eq 0) {
            & $add 'Acer WMI class' 'ok' 'AcerGamingFunction with the expected fan methods'
        }
        else {
            & $add 'Acer WMI class' 'warn' ("Missing methods: {0}" -f ($missing -join ', '))
        }
    }
    catch {
        & $add 'Acer WMI class' 'fail' $_.Exception.Message
    }

    $instance = $null
    if ($admin) {
        try {
            $instance = Get-AcerGamingInstance
            & $add 'Acer WMI instance' 'ok' ([string]$instance.InstanceName)
        }
        catch {
            & $add 'Acer WMI instance' 'fail' $_.Exception.Message
        }
    }

    if ($instance) {
        try {
            $supported = Get-AcerSupportedSensor -Instance $instance
            & $add 'Supported sensors' 'ok' ('0x{0:X4}' -f $supported)
        }
        catch {
            & $add 'Supported sensors' 'warn' $_.Exception.Message
        }

        foreach ($sensor in @('CpuTemperature', 'GpuTemperature', 'CpuFanRpm', 'GpuFanRpm')) {
            try {
                $reading = Get-AcerGamingSysInfo -Instance $instance -Sensor $sensor
                if ($reading.Status -eq 0 -and $reading.Value -gt 0) {
                    & $add $sensor 'ok' ("{0} (status 0)" -f $reading.Value)
                }
                else {
                    & $add $sensor 'warn' ("status {0}, value {1}" -f $reading.Status, $reading.Value)
                }
            }
            catch {
                & $add $sensor 'warn' $_.Exception.Message
            }
        }

        try {
            $mode = Get-AcerFanMode -Instance $instance
            & $add 'Fan mode' 'ok' ("CPU={0} GPU={1}" -f $mode.Cpu, $mode.Gpu)
        }
        catch {
            & $add 'Fan mode' 'warn' $_.Exception.Message
        }

        $config = $null
        try {
            $config = Import-FanCurveConfig -Path $ConfigPath
        }
        catch {
            & $add 'Config' 'fail' $_.Exception.Message
        }
        if ($config) {
            foreach ($fanName in @('cpu', 'gpu')) {
                $fanId = $config['fans'][$fanName]
                if ($null -eq $fanId) {
                    continue
                }
                try {
                    $speed = Get-AcerFanSpeed -Instance $instance -FanId ([int]$fanId)
                    & $add ("Fan {0} (id {1})" -f $fanName.ToUpper(), $fanId) 'ok' ("{0}% (status 0)" -f $speed.Percent)
                }
                catch {
                    & $add ("Fan {0} (id {1})" -f $fanName.ToUpper(), $fanId) 'warn' $_.Exception.Message
                }
            }
        }
    }

    try {
        $nitro = Get-Process -Name 'NitroSense' -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($nitro) {
            & $add 'NitroSense' 'ok' 'Running with a readable window (fallback provider)'
        }
        else {
            & $add 'NitroSense' 'warn' 'Process exists but no window is available.'
        }
    }
    catch {
        & $add 'NitroSense' 'warn' 'Not running. The UI fallback will not be available.'
    }

    try {
        $temperatures = Get-FanCurveTemperature -Provider 'auto'
        & $add 'Temperature probe' 'ok' ("CPU {0} C, GPU {1} C via {2}" -f $temperatures.Cpu, $temperatures.Gpu, $temperatures.Source)
    }
    catch {
        & $add 'Temperature probe' 'fail' $_.Exception.Message
    }

    $configPathResolved = if ($ConfigPath) { $ConfigPath } else { Get-FanCurveConfigPath }
    if ($configPathResolved) {
        try {
            $config = Import-FanCurveConfig -Path $configPathResolved
            $validation = Test-FanCurveConfig -Config $config
            if ($validation.Valid) {
                & $add 'Config file' 'ok' $configPathResolved
            }
            else {
                & $add 'Config file' 'fail' ($validation.Errors -join '; ')
            }
        }
        catch {
            & $add 'Config file' 'fail' $_.Exception.Message
        }
    }
    else {
        & $add 'Config file' 'warn' 'No config file found; built-in defaults will be used.'
    }

    $task = Get-FanCurveTaskStatus
    if ($task.Installed) {
        & $add 'Scheduled task' 'ok' ("{0}; last result {1}" -f $task.State, $task.LastTaskResultText)
    }
    else {
        & $add 'Scheduled task' 'warn' 'Not installed. Run .\fancurve.ps1 install.'
    }

    $modelName = 'Unknown'
    if ($system.Model) {
        $modelName = "$($system.Manufacturer) $($system.Model)"
    }
    $checkArray = $checks.ToArray()

    return [pscustomobject]@{
        Version = $script:FanCurveVersion
        Model = $modelName
        Administrator = $admin
        Checks = $checkArray
    }
}

function Format-FanCurveDoctor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Result
    )

    Write-Output ("FanCurve doctor - {0}" -f $Result.Model)
    Write-Output ''
    foreach ($check in $Result.Checks) {
        $label = switch ($check.Status) {
            'ok' { '[ok]  ' }
            'warn' { '[warn]' }
            default { '[fail]' }
        }
        Write-Output ("{0} {1}: {2}" -f $label, $check.Name, $check.Detail)
    }
}

#endregion

#region Installation and elevation

function Request-FanCurveElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $executable = (Get-Process -Id $PID).Path
    $escapedArguments = @()
    foreach ($argument in $ArgumentList) {
        if ($argument -match '\s') {
            $escapedArguments += ('"{0}"' -f $argument)
        }
        else {
            $escapedArguments += $argument
        }
    }

    $argumentString = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $ScriptPath, ($escapedArguments -join ' ')).TrimEnd()

    try {
        $process = Start-Process -FilePath $executable -Verb RunAs -ArgumentList $argumentString -Wait -PassThru -ErrorAction Stop
        return $process.ExitCode
    }
    catch {
        throw "Elevation was cancelled or failed: $($_.Exception.Message)"
    }
}

function Register-FanCurveTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [string]$TaskName = 'FanCurve',
        [switch]$NoStart
    )

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        $executable = $pwsh.Source
    }
    else {
        $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
        if (-not $powershell) {
            throw 'Neither pwsh.exe nor powershell.exe was found.'
        }
        $executable = $powershell.Source
    }

    $user = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" run -Config "{1}"' -f $ScriptPath, $ConfigPath

    $action = New-ScheduledTaskAction -Execute $executable -Argument $arguments -WorkingDirectory (Split-Path -Parent $ScriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    try {
        $trigger.Delay = 'PT30S'
    }
    catch {
        Write-Verbose "The logon trigger does not support a startup delay: $($_.Exception.Message)"
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Force | Out-Null

    if (-not $NoStart) {
        Start-ScheduledTask -TaskName $TaskName
    }
}

function Unregister-FanCurveTask {
    [CmdletBinding()]
    param(
        [string]$TaskName = 'FanCurve'
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return
    }

    if ($task.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Install-FanCurve {
    [CmdletBinding()]
    param(
        [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),
        [string]$InstallPath = (Get-FanCurveInstallPath),
        [string]$DataPath = (Get-FanCurveDataPath),
        [string]$ConfigPath,
        [string]$TaskName = 'FanCurve',
        [switch]$NoStart,
        [switch]$ResetConfig
    )

    if (-not (Test-FanCurveAdmin)) {
        throw 'Install requires an elevated PowerShell session.'
    }

    $source = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $required = @(
        (Join-Path $source 'fancurve.ps1'),
        (Join-Path $source 'src\FanCurve.psm1'),
        (Join-Path $source 'src\FanCurve.psd1'),
        (Join-Path $source 'config\fancurve.example.json')
    )
    foreach ($file in $required) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "Install source is missing '$file'."
        }
    }

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        if ($existingTask.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        try {
            Restore-AcerFanAuto
        }
        catch {
            Write-Verbose "AUTO mode could not be restored during install: $($_.Exception.Message)"
        }
    }

    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    New-Item -ItemType Directory -Path $DataPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $DataPath 'logs') -Force | Out-Null

    if ($source -ne $InstallPath) {
        Copy-Item -LiteralPath (Join-Path $source 'fancurve.ps1') -Destination $InstallPath -Force
        Copy-Item -LiteralPath (Join-Path $source 'src') -Destination $InstallPath -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $source 'config') -Destination $InstallPath -Recurse -Force
        foreach ($extra in @('README.md', 'LICENSE')) {
            $extraPath = Join-Path $source $extra
            if (Test-Path -LiteralPath $extraPath) {
                Copy-Item -LiteralPath $extraPath -Destination $InstallPath -Force
            }
        }
    }

    $installedConfig = Join-Path $DataPath 'config.json'
    $installedSchema = Join-Path $DataPath 'fancurve.schema.json'
    $exampleSchema = Join-Path $source 'config\fancurve.schema.json'
    if (Test-Path -LiteralPath $exampleSchema) {
        Copy-Item -LiteralPath $exampleSchema -Destination $installedSchema -Force
    }

    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "Config file '$ConfigPath' was not found."
        }
        Copy-Item -LiteralPath $ConfigPath -Destination $installedConfig -Force
    }
    elseif ($ResetConfig -or -not (Test-Path -LiteralPath $installedConfig)) {
        Copy-Item -LiteralPath (Join-Path $source 'config\fancurve.example.json') -Destination $installedConfig -Force
    }

    $installedScript = Join-Path $InstallPath 'fancurve.ps1'
    Register-FanCurveTask -ScriptPath $installedScript -ConfigPath $installedConfig -TaskName $TaskName -NoStart:$NoStart

    return [pscustomobject]@{
        InstallPath = $InstallPath
        DataPath = $DataPath
        ConfigPath = $installedConfig
        ScriptPath = $installedScript
        TaskName = $TaskName
        Started = (-not $NoStart)
    }
}

function Uninstall-FanCurve {
    [CmdletBinding()]
    param(
        [string]$InstallPath = (Get-FanCurveInstallPath),
        [string]$DataPath = (Get-FanCurveDataPath),
        [string]$TaskName = 'FanCurve',
        [switch]$KeepConfig
    )

    if (-not (Test-FanCurveAdmin)) {
        throw 'Uninstall requires an elevated PowerShell session.'
    }

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        if ($task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    try {
        Restore-AcerFanAuto
    }
    catch {
        Write-Verbose "AUTO mode could not be restored during uninstall: $($_.Exception.Message)"
    }

    Unregister-FanCurveTask -TaskName $TaskName

    if (Test-Path -LiteralPath $InstallPath) {
        Remove-Item -LiteralPath $InstallPath -Recurse -Force
    }

    if (-not $KeepConfig -and (Test-Path -LiteralPath $DataPath)) {
        Remove-Item -LiteralPath $DataPath -Recurse -Force
    }

    return [pscustomobject]@{
        InstallPath = $InstallPath
        DataPath = $DataPath
        TaskName = $TaskName
        ConfigKept = [bool]$KeepConfig
    }
}

function Show-FanCurveHelp {
    [CmdletBinding()]
    param()

    @'
FanCurve - a configurable fan curve controller for Acer Nitro and Predator laptops.

Usage:
  .\fancurve.ps1 run [-Config <path>] [-LogPath <path>] [-LogLevel <level>] [-DryRun] [-Once] [-NoRestore]
  .\fancurve.ps1 status [-Config <path>] [-Json]
  .\fancurve.ps1 doctor [-Config <path>] [-Json]
  .\fancurve.ps1 install [-NoStart] [-ResetConfig] [-NoElevate]
  .\fancurve.ps1 uninstall [-KeepConfig] [-NoElevate]
  .\fancurve.ps1 restore [-NoElevate]
  .\fancurve.ps1 version
  .\fancurve.ps1 help

Run without a command to show this help.

Commands:
  run        Start the controller (elevated for fan writes).
  status     Show the current mode, fan speeds, temperatures and task state.
  doctor     Check the machine, Acer WMI interface, sensors and config.
  install    Copy FanCurve to Program Files and register the logon task.
  uninstall  Stop the task, restore AUTO and remove the install.
  restore    Stop the task and put the fans back on the firmware curve.
  version    Print the FanCurve version.
  help       Show this help.

Examples:
  .\fancurve.ps1 doctor
  .\fancurve.ps1 run -DryRun -Once
  .\fancurve.ps1 install
  .\fancurve.ps1 status -Json
'@
}

#endregion

Export-ModuleMember -Function @(
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
