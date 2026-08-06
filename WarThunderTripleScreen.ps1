param(
    [string]$Config = "",
    [switch]$DryRun,
    [switch]$NoLaunch,
    [switch]$Attach,
    [switch]$RestoreConfig,
    [switch]$RestoreDisplay,
    [switch]$LibraryOnly
)

$ErrorActionPreference = "Stop"

$isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
$runningOnWindows = if ($isWindowsVariable) { [bool]$isWindowsVariable.Value } else { [Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT }
if (-not $runningOnWindows) { throw "WarThunderTripleScreen.ps1 must run on Windows." }

if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path $PSScriptRoot "WarThunderTripleScreen.ini" }
$LogRoot = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$LogPath = Join-Path $LogRoot ("WarThunderTripleScreen-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$DisplayStatePath = Join-Path $LogRoot "display-restore-state.json"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line
}

function Read-IniFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Configuration file not found: $Path" }
    $data = @{ default = @{} }; $section = "default"
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(";") -or $line.StartsWith("#")) { continue }
        if ($line -match '^\[(.+)\]$') { $section = $matches[1].Trim(); if (-not $data.ContainsKey($section)) { $data[$section] = @{} }; continue }
        $index = $line.IndexOf("="); if ($index -lt 1) { continue }
        $data[$section][$line.Substring(0, $index).Trim()] = $line.Substring($index + 1).Trim()
    }
    return $data
}

function Get-IniValue {
    param([hashtable]$Ini, [string]$Section, [string]$Key, [string]$Default)
    if ($Ini.ContainsKey($Section) -and $Ini[$Section].ContainsKey($Key)) { return [string]$Ini[$Section][$Key] }
    return $Default
}

function Get-IniInt {
    param([hashtable]$Ini, [string]$Section, [string]$Key, [int]$Default)
    $parsed = 0; $value = Get-IniValue $Ini $Section $Key ([string]$Default)
    if ([int]::TryParse($value, [ref]$parsed)) { return $parsed }
    return $Default
}

function Get-IniBool {
    param([hashtable]$Ini, [string]$Section, [string]$Key, [bool]$Default)
    switch ((Get-IniValue $Ini $Section $Key ([string]$Default)).Trim().ToLowerInvariant()) {
        { $_ -in @("1", "true", "yes", "on") } { return $true }
        { $_ -in @("0", "false", "no", "off") } { return $false }
        default { return $Default }
    }
}

if (-not ("WarThunderTripleScreen.Native" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WarThunderTripleScreen {
    public class DisplayModeInfo {
        public string Device; public int X; public int Y; public int Width; public int Height;
        public int Frequency; public int BitsPerPixel; public int Orientation;
    }
    public class MonitorScaleInfo {
        public int X; public int Y; public int Width; public int Height; public int Scale;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
            public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
            public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight;
            public int dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType;
            public int dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, ref RECT rect, IntPtr data);
        [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data);
        [DllImport("shcore.dll")] private static extern int GetScaleFactorForMonitor(IntPtr monitor, out int scale);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern bool EnumDisplaySettingsEx(string device, int mode, ref DEVMODE dm, int flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int ChangeDisplaySettingsEx(string device, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr param);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int ChangeDisplaySettingsEx(string device, IntPtr dm, IntPtr hwnd, int flags, IntPtr param);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll", SetLastError=true)] public static extern int SetWindowLong(IntPtr hwnd, int index, int value);

        private static DEVMODE EmptyMode() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }
        private static DisplayModeInfo Info(string device, DEVMODE d) { return new DisplayModeInfo { Device=device, X=d.dmPositionX, Y=d.dmPositionY, Width=d.dmPelsWidth, Height=d.dmPelsHeight, Frequency=d.dmDisplayFrequency, BitsPerPixel=d.dmBitsPerPel, Orientation=d.dmDisplayOrientation }; }
        public static DisplayModeInfo CurrentMode(string device) { DEVMODE d=EmptyMode(); if(!EnumDisplaySettingsEx(device,-1,ref d,0)) throw new InvalidOperationException("Cannot read display mode for " + device); return Info(device,d); }
        public static DisplayModeInfo[] Modes(string device) { var list=new List<DisplayModeInfo>(); for(int i=0;;i++){ DEVMODE d=EmptyMode(); if(!EnumDisplaySettingsEx(device,i,ref d,0)) break; list.Add(Info(device,d)); } return list.ToArray(); }
        public static int StageMode(string device, int width, int height, int frequency, int x, int y) {
            DEVMODE chosen=EmptyMode(); bool found=false;
            for(int i=0;;i++){ DEVMODE d=EmptyMode(); if(!EnumDisplaySettingsEx(device,i,ref d,0)) break; if(d.dmPelsWidth==width && d.dmPelsHeight==height && (frequency<=0 || d.dmDisplayFrequency==frequency)){ chosen=d; found=true; break; } }
            if(!found) return -2;
            chosen.dmPositionX=x; chosen.dmPositionY=y; chosen.dmFields |= 0x00000020 | 0x00080000 | 0x00100000 | 0x00400000;
            return ChangeDisplaySettingsEx(device,ref chosen,IntPtr.Zero,0x10000001,IntPtr.Zero);
        }
        public static int CommitModes() { return ChangeDisplaySettingsEx(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero); }
        public static MonitorScaleInfo[] MonitorScales() {
            var list=new List<MonitorScaleInfo>(); MonitorEnumProc cb=delegate(IntPtr m,IntPtr h,ref RECT r,IntPtr d){int scale=100; try{GetScaleFactorForMonitor(m,out scale);}catch{} list.Add(new MonitorScaleInfo{X=r.Left,Y=r.Top,Width=r.Right-r.Left,Height=r.Bottom-r.Top,Scale=scale}); return true;};
            EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,cb,IntPtr.Zero); return list.ToArray();
        }
    }
}
"@
}

Add-Type -AssemblyName System.Windows.Forms
[void][WarThunderTripleScreen.Native]::SetProcessDpiAwarenessContext([IntPtr](-4))

function Get-ScreenSnapshot {
    $screens = foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $mode = [WarThunderTripleScreen.Native]::CurrentMode($screen.DeviceName)
        [pscustomobject]@{ Device=$screen.DeviceName; Primary=$screen.Primary; X=$screen.Bounds.X; Y=$screen.Bounds.Y; Width=$screen.Bounds.Width; Height=$screen.Bounds.Height; Frequency=$mode.Frequency; BitsPerPixel=$mode.BitsPerPixel; Orientation=$mode.Orientation }
    }
    return @($screens)
}

function Get-PrimaryRow {
    param([object[]]$Screens, [hashtable]$Ini)
    $primary = $Screens | Where-Object Primary | Select-Object -First 1
    if (-not $primary) { throw "Windows did not report a primary monitor." }
    $row = @($Screens | Where-Object { $_.Y -lt ($primary.Y + $primary.Height) -and ($_.Y + $_.Height) -gt $primary.Y } | Sort-Object X)
    $required = Get-IniInt $Ini "Layout" "RequiredMonitors" 3
    if ($required -gt 0 -and $row.Count -ne $required) { throw "Expected $required monitors in the primary row, detected $($row.Count)." }
    if ((Get-IniBool $Ini "Layout" "RequirePrimaryInMiddle" $true) -and $row.Count -eq 3 -and -not $row[1].Primary) { throw "The primary monitor must be the centre display in the three-monitor row." }
    return $row
}

function Write-ScreenLog {
    param([object[]]$Screens)
    Write-Log ("Detected {0} active screen(s)." -f $Screens.Count)
    foreach ($s in $Screens) { Write-Log ("Screen {0}: primary={1} x={2} y={3} {4}x{5} {6}Hz" -f $s.Device,$s.Primary,$s.X,$s.Y,$s.Width,$s.Height,$s.Frequency) }
}

function Test-MonitorScale {
    param([object[]]$Row, [hashtable]$Ini)
    if (-not (Get-IniBool $Ini "Display" "Require100PercentScale" $true)) { return }
    foreach ($scale in [WarThunderTripleScreen.Native]::MonitorScales()) {
        foreach ($s in $Row) {
            if ($scale.X -eq $s.X -and $scale.Y -eq $s.Y -and $scale.Width -eq $s.Width -and $scale.Height -eq $s.Height -and $scale.Scale -ne 100) {
                throw "Display $($s.Device) uses $($scale.Scale)% Windows scaling. Set every target display to 100% to avoid an enlarged/cropped game window."
            }
        }
    }
}

function Get-DisplayPlan {
    param([object[]]$Row, [hashtable]$Ini)
    $primary = $Row | Where-Object Primary | Select-Object -First 1
    $autoPromote = Get-IniBool $Ini "Display" "AutoPromoteToPrimary" $true
    $plans = @()
    foreach ($s in $Row) {
        $width=$s.Width; $height=$s.Height; $frequency=$s.Frequency
        if (($s.Width -ne $primary.Width -or $s.Height -ne $primary.Height) -and $autoPromote) {
            $matches = @([WarThunderTripleScreen.Native]::Modes($s.Device) | Where-Object { $_.Width -eq $primary.Width -and $_.Height -eq $primary.Height })
            if ($matches.Count -eq 0) {
                throw ("{0} is {1}x{2} and does not expose {3}x{4}. Enable the NVIDIA DSR/DLDSR mode for this side display first; the wrapper deliberately does not invent unsupported driver modes." -f $s.Device,$s.Width,$s.Height,$primary.Width,$primary.Height)
            }
            $preferred = $matches | Where-Object Frequency -eq $s.Frequency | Select-Object -First 1
            if (-not $preferred) { $preferred = $matches | Sort-Object Frequency -Descending | Select-Object -First 1 }
            $width=$preferred.Width; $height=$preferred.Height; $frequency=$preferred.Frequency
        }
        $plans += [pscustomobject]@{ Device=$s.Device; Primary=$s.Primary; OldX=$s.X; OldY=$s.Y; OldWidth=$s.Width; OldHeight=$s.Height; OldFrequency=$s.Frequency; X=0; Y=$primary.Y; Width=$width; Height=$height; Frequency=$frequency }
    }
    $primaryIndex = 0; for ($i=0; $i -lt $plans.Count; $i++) { if ($plans[$i].Primary) { $primaryIndex=$i; break } }
    $plans[$primaryIndex].X = $primary.X
    $cursor = $primary.X
    for ($i=$primaryIndex-1; $i -ge 0; $i--) { $cursor -= $plans[$i].Width; $plans[$i].X=$cursor }
    $cursor = $primary.X + $plans[$primaryIndex].Width
    for ($i=$primaryIndex+1; $i -lt $plans.Count; $i++) { $plans[$i].X=$cursor; $cursor += $plans[$i].Width }
    if (Get-IniBool $Ini "Layout" "RequireEqualHeight" $true) {
        foreach ($p in $plans) { if ($p.Height -ne $primary.Height) { throw "Target display heights are not equal." } }
    }
    return $plans
}

function Get-TargetFromPlan {
    param([object[]]$Plan)
    $left=($Plan|Measure-Object X -Minimum).Minimum; $top=($Plan|Measure-Object Y -Minimum).Minimum
    $right=($Plan|ForEach-Object {$_.X+$_.Width}|Measure-Object -Maximum).Maximum; $bottom=($Plan|ForEach-Object {$_.Y+$_.Height}|Measure-Object -Maximum).Maximum
    return [pscustomobject]@{ X=[int]$left; Y=[int]$top; Width=[int]($right-$left); Height=[int]($bottom-$top) }
}

function Save-DisplayState {
    param([object[]]$Plan)
    $state = @($Plan | ForEach-Object { [pscustomobject]@{Device=$_.Device;X=$_.OldX;Y=$_.OldY;Width=$_.OldWidth;Height=$_.OldHeight;Frequency=$_.OldFrequency} })
    $temp="$DisplayStatePath.tmp"; $state | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding UTF8; Move-Item -LiteralPath $temp -Destination $DisplayStatePath -Force
}

function Apply-DisplayPlan {
    param([object[]]$Plan)
    foreach ($p in $Plan) {
        $result=[WarThunderTripleScreen.Native]::StageMode($p.Device,$p.Width,$p.Height,$p.Frequency,$p.X,$p.Y)
        if ($result -ne 0) { throw "Windows rejected the staged mode for $($p.Device) with result $result." }
    }
    $result=[WarThunderTripleScreen.Native]::CommitModes(); if ($result -ne 0) { throw "Windows rejected the display layout with result $result." }
}

function Restore-DisplayState {
    if (-not (Test-Path -LiteralPath $DisplayStatePath)) { throw "No saved display state was found at $DisplayStatePath" }
    $state=@(Get-Content -Raw -LiteralPath $DisplayStatePath | ConvertFrom-Json)
    foreach ($s in $state) {
        $result=[WarThunderTripleScreen.Native]::StageMode([string]$s.Device,[int]$s.Width,[int]$s.Height,[int]$s.Frequency,[int]$s.X,[int]$s.Y)
        if ($result -ne 0) { throw "Windows rejected the restore mode for $($s.Device) with result $result." }
    }
    $result=[WarThunderTripleScreen.Native]::CommitModes(); if ($result -ne 0) { throw "Windows rejected the restored display layout with result $result." }
    Remove-Item -LiteralPath $DisplayStatePath -Force
    Write-Log "Restored the saved Windows display layout."
}

function Find-GameRoot {
    param([hashtable]$Ini)
    $configured=Get-IniValue $Ini "Game" "InstallRoot" ""
    $candidates=@($configured,"F:\ENTERTAINMENT\GAMES\WarThunder",(Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\War Thunder"),(Join-Path $env:ProgramFiles "War Thunder")) | Where-Object { $_ }
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath (Join-Path $candidate "config.blk")) { return (Resolve-Path -LiteralPath $candidate).Path } }
    throw "War Thunder was not found. Set Game.InstallRoot in WarThunderTripleScreen.ini."
}

function Write-AtomicText {
    param([string]$Path,[string]$Text)
    $temp="$Path.WarThunderTripleScreen.tmp"; $encoding=New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($temp,$Text,$encoding); Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Set-WarThunderConfig {
    param([string]$GameRoot,[object]$Target,[hashtable]$Ini)
    $path=Join-Path $GameRoot "config.blk"; $text=[IO.File]::ReadAllText($path)
    if (Get-IniBool $Ini "Config" "Backup" $true) { $backup="$path.WarThunderTripleScreen.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"; Copy-Item -LiteralPath $path -Destination $backup; Write-Log "Backed up config.blk to $backup" }
    $resolution='resolution:t="{0} x {1}"' -f $Target.Width,$Target.Height
    if ($text -notmatch '(?m)^\s*resolution:t=') { throw "config.blk has no video resolution entry." }
    $text=[regex]::Replace($text,'(?m)^\s*resolution:t="[^"]*"',$resolution,1)
    $mode=Get-IniValue $Ini "Config" "Mode" "windowed"
    $text=[regex]::Replace($text,'(?m)^\s*mode:t="[^"]*"',('mode:t="{0}"' -f $mode),1)
    $text=[regex]::Replace($text,'(?m)^\s*windowed:b=(yes|no)','windowed:b=yes',1)
    Write-AtomicText $path $text; Write-Log ("Configured War Thunder for {0}x{1} {2}." -f $Target.Width,$Target.Height,$mode)
}

function Restore-WarThunderConfig {
    param([string]$GameRoot)
    $path=Join-Path $GameRoot "config.blk"; $backup=Get-ChildItem -LiteralPath $GameRoot -Filter "config.blk.WarThunderTripleScreen.backup-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $backup) { throw "No WarThunderTripleScreen config backup was found in $GameRoot" }
    Copy-Item -LiteralPath $backup.FullName -Destination $path -Force; Write-Log "Restored config.blk from $($backup.FullName)"
}

function Get-GameWindow {
    param([string]$Name,[int]$WaitSeconds)
    if ($Name.EndsWith(".exe")) { $Name=$Name.Substring(0,$Name.Length-4) }
    $deadline=(Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in [Diagnostics.Process]::GetProcessesByName($Name)) { try { $process.Refresh(); if ($process.MainWindowHandle -ne [IntPtr]::Zero) { return $process } } catch {} }
        Start-Sleep -Milliseconds 500
    }
    throw "No visible $Name window appeared within $WaitSeconds seconds."
}

function Get-WindowRectangle {
    param([IntPtr]$Handle)
    if (-not [WarThunderTripleScreen.Native]::IsWindow($Handle)) { return $null }
    $rect=New-Object WarThunderTripleScreen.Native+RECT
    if (-not [WarThunderTripleScreen.Native]::GetWindowRect($Handle,[ref]$rect)) { return $null }
    return [pscustomobject]@{X=$rect.Left;Y=$rect.Top;Width=$rect.Right-$rect.Left;Height=$rect.Bottom-$rect.Top}
}

function Test-RectangleClose {
    param([object]$Actual,[object]$Target,[int]$Tolerance)
    return $Actual -and [Math]::Abs($Actual.X-$Target.X) -le $Tolerance -and [Math]::Abs($Actual.Y-$Target.Y) -le $Tolerance -and [Math]::Abs($Actual.Width-$Target.Width) -le $Tolerance -and [Math]::Abs($Actual.Height-$Target.Height) -le $Tolerance
}

function Set-GameWindow {
    param([IntPtr]$Handle,[object]$Target,[bool]$RemoveBorders)
    if ($RemoveBorders) {
        $style=[WarThunderTripleScreen.Native]::GetWindowLong($Handle,-16); $borderMask=0x00C00000 -bor 0x00040000
        [void][WarThunderTripleScreen.Native]::SetWindowLong($Handle,-16,($style -band (-bnot $borderMask)))
    }
    [void][WarThunderTripleScreen.Native]::ShowWindow($Handle,9)
    $flags=0x0004 -bor 0x0020 -bor 0x0040
    if (-not [WarThunderTripleScreen.Native]::SetWindowPos($Handle,[IntPtr]::Zero,$Target.X,$Target.Y,$Target.Width,$Target.Height,$flags)) { throw "SetWindowPos failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())." }
}

function Stabilize-GameWindow {
    param([Diagnostics.Process]$Process,[object]$Target,[hashtable]$Ini)
    $seconds=Get-IniInt $Ini "Window" "StabilizeSeconds" 45; $interval=Get-IniInt $Ini "Window" "IntervalMilliseconds" 750; $tolerance=Get-IniInt $Ini "Window" "TolerancePixels" 2; $max=Get-IniInt $Ini "Window" "MaxCorrections" 20
    $remove=Get-IniBool $Ini "Window" "RemoveBorders" $true; $deadline=(Get-Date).AddSeconds($seconds); $corrections=0
    do {
        $Process.Refresh(); if ($Process.HasExited) { throw "War Thunder exited before its window stabilized." }
        $handle=$Process.MainWindowHandle; $actual=Get-WindowRectangle $handle
        if (-not (Test-RectangleClose $actual $Target $tolerance)) {
            if ($corrections -ge $max) { throw "War Thunder kept changing its window; stopped after $corrections corrections." }
            Set-GameWindow $handle $Target $remove; $corrections++; Write-Log ("Applied x={0} y={1} {2}x{3}; correction {4}." -f $Target.X,$Target.Y,$Target.Width,$Target.Height,$corrections)
        }
        Start-Sleep -Milliseconds $interval
    } while ((Get-Date) -lt $deadline)
    $final=Get-WindowRectangle $Process.MainWindowHandle
    if (-not (Test-RectangleClose $final $Target $tolerance)) { throw "The final War Thunder window does not match the target rectangle." }
    Write-Log ("Window stable at x={0} y={1} {2}x{3}." -f $final.X,$final.Y,$final.Width,$final.Height)
}

if ($LibraryOnly) { return }

$ini=Read-IniFile $Config
Write-Log "War Thunder Triple Screen started."
Write-Log "Safety boundary: external config and top-level window APIs only; no injection, game-memory access, renderer hook, or anti-cheat bypass."

if ($RestoreDisplay) { Restore-DisplayState; exit 0 }
$gameRoot=Find-GameRoot $ini
if ($RestoreConfig) { Restore-WarThunderConfig $gameRoot; exit 0 }

$screens=Get-ScreenSnapshot; Write-ScreenLog $screens; $row=Get-PrimaryRow $screens $ini; Test-MonitorScale $row $ini
$plan=Get-DisplayPlan $row $ini; $target=Get-TargetFromPlan $plan
foreach ($p in $plan) { Write-Log ("Plan {0}: {1}x{2}@{3} -> x={4} y={5} {6}x{7}@{8}" -f $p.Device,$p.OldWidth,$p.OldHeight,$p.OldFrequency,$p.X,$p.Y,$p.Width,$p.Height,$p.Frequency) }
Write-Log ("Target: x={0} y={1} width={2} height={3}." -f $target.X,$target.Y,$target.Width,$target.Height)

$needsDisplayChange=@($plan | Where-Object { $_.OldX-ne$_.X -or $_.OldY-ne$_.Y -or $_.OldWidth-ne$_.Width -or $_.OldHeight-ne$_.Height -or $_.OldFrequency-ne$_.Frequency }).Count -gt 0
if ($DryRun) { Write-Log "Dry run complete: no display, config, launcher, or window changes were made."; exit 0 }

$processName=Get-IniValue $ini "Game" "ProcessName" "aces"
$existing=@([Diagnostics.Process]::GetProcessesByName($processName))
if ($Attach) {
    if ($needsDisplayChange) { throw "Attach mode will not change display modes while War Thunder is running. Put all three displays at the same effective resolution first." }
    Write-Log "Attach mode: config, display modes, and launcher will not be changed."
    $wait=Get-IniInt $ini "Window" "WaitSeconds" 240
    $game=Get-GameWindow $processName $wait
    Write-Log ("Found existing {0}.exe pid={1}." -f $game.ProcessName,$game.Id)
    Stabilize-GameWindow $game $target $ini
    Write-Log "Current War Thunder window corrected."
    exit 0
}
if ($existing.Count -gt 0 -and (Get-IniBool $ini "Game" "RequireClosedBeforeConfig" $true)) { throw "Close War Thunder before running the wrapper so the new render resolution is applied at startup." }
if ($needsDisplayChange -and (Test-Path -LiteralPath $DisplayStatePath)) { throw "A previous display restore state already exists. Run .\WarThunderTripleScreen.ps1 -RestoreDisplay before continuing." }

$displayChanged=$false
try {
    if ($needsDisplayChange) { Save-DisplayState $plan; Apply-DisplayPlan $plan; $displayChanged=$true; Write-Log "Applied the temporary equal-resolution display row." }
    Set-WarThunderConfig $gameRoot $target $ini
    if (-not $NoLaunch -and (Get-IniBool $ini "Game" "AutoLaunchLauncher" $true)) {
        $launcher=Get-IniValue $ini "Game" "LauncherPath" ""; if (-not $launcher) { $launcher=Join-Path $gameRoot "launcher.exe" }
        if (-not (Test-Path -LiteralPath $launcher)) { throw "War Thunder launcher not found: $launcher" }
        Start-Process -FilePath $launcher | Out-Null; Write-Log "Started the official War Thunder launcher. Click Play if it does not start the game automatically."
    } else { Write-Log "Launch War Thunder through its normal launcher; waiting for the game window." }
    $wait=Get-IniInt $ini "Window" "WaitSeconds" 240; $game=Get-GameWindow $processName $wait
    Write-Log ("Found {0}.exe pid={1}." -f $game.ProcessName,$game.Id)
    Stabilize-GameWindow $game $target $ini
    if ($displayChanged -and (Get-IniBool $ini "Display" "RestoreAfterGame" $true)) { Write-Log "Waiting for War Thunder to close before restoring the previous display layout."; $game.WaitForExit() }
} finally {
    if ($displayChanged -and (Get-IniBool $ini "Display" "RestoreAfterGame" $true)) {
        try { Restore-DisplayState } catch { Write-Log ("Automatic display restore failed: {0}. Run with -RestoreDisplay." -f $_.Exception.Message) "ERROR" }
    }
}
Write-Log "Done. Log: $LogPath"
