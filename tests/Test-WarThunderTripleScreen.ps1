$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root "WarThunderTripleScreen.ps1"
$source = Get-Content -Raw -LiteralPath $script

foreach ($required in @(
    "AutoPromoteToPrimary",
    "display-restore-state.json",
    "Set-WarThunderConfig",
    "Write-AtomicText",
    "no injection, game-memory access, renderer hook, or anti-cheat bypass",
    "War Thunder kept changing its window",
    "Attach mode: config, display modes, and launcher will not be changed",
    "Require100PercentScale"
)) {
    if (-not $source.Contains($required)) { throw "Missing safety or recovery feature: $required" }
}

$ini = Get-Content -Raw -LiteralPath (Join-Path $root "WarThunderTripleScreen.ini")
foreach ($required in @("RequiredMonitors=3", "RestoreAfterGame=true", "RequireClosedBeforeConfig=true")) {
    if (-not $ini.Contains($required)) { throw "Missing safe default: $required" }
}

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | ForEach-Object Message | Out-String) }

Write-Output "PASS: PowerShell syntax and triple-screen safety/recovery guards"

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("WarThunderTripleScreen-test-{0}" -f [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $fixtureConfig = Join-Path $testRoot "config.blk"
    Set-Content -LiteralPath $fixtureConfig -Encoding ASCII -Value @(
        'language:t="English"',
        'video{',
        '  resolution:t="1920 x 1080"',
        '  mode:t="fullscreen"',
        '  windowed:b=no',
        '}',
        'unrelated:t="preserved"'
    )
    $fixtureIniPath = Join-Path $testRoot "test.ini"
    Set-Content -LiteralPath $fixtureIniPath -Encoding ASCII -Value @(
        '[Config]',
        'Backup=true',
        'Mode=windowed'
    )

    . $script -LibraryOnly
    $fixtureIni = Read-IniFile $fixtureIniPath
    $target = [pscustomobject]@{ X=-2560; Y=0; Width=7680; Height=1440 }
    Set-WarThunderConfig $testRoot $target $fixtureIni

    $updated = Get-Content -Raw -LiteralPath $fixtureConfig
    foreach ($expected in @('resolution:t="7680 x 1440"', 'mode:t="windowed"', 'windowed:b=yes', 'unrelated:t="preserved"')) {
        if (-not $updated.Contains($expected)) { throw "Disposable config is missing: $expected" }
    }
    $backups = @(Get-ChildItem -LiteralPath $testRoot -Filter "config.blk.WarThunderTripleScreen.backup-*")
    if ($backups.Count -ne 1) { throw "Expected one disposable config backup, found $($backups.Count)." }

    $syntheticPlan = @(
        [pscustomobject]@{X=-2560;Y=0;Width=2560;Height=1440},
        [pscustomobject]@{X=0;Y=0;Width=2560;Height=1440},
        [pscustomobject]@{X=2560;Y=0;Width=2560;Height=1440}
    )
    $syntheticTarget = Get-TargetFromPlan $syntheticPlan
    if ($syntheticTarget.X -ne -2560 -or $syntheticTarget.Width -ne 7680 -or $syntheticTarget.Height -ne 1440) {
        throw "Synthetic triple-monitor target calculation failed."
    }
    Write-Output "PASS: disposable config backup/rewrite and 7680x1440 target calculation"
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path
        if (-not $resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove test path outside TEMP: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
