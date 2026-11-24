[CmdletBinding()]
param([switch]$Interactive, [switch]$Elevated, [switch]$Help, [switch]$Yes)
$ErrorActionPreference = 'Stop'
if ($Help) {
    Write-Host 'WinRep 1.3.0 - Windows component and system file repair.'
    Write-Host 'Double-click winrep.cmd for the interactive interface. Requires Windows 10/11 and administrator rights.'
    Write-Host 'A confirmation is required unless the technician explicitly supplies -Yes.'
    exit 0
}

function Wait-ForUser {
    if ($Interactive) { [void](Read-Host 'Press Enter to close') }
}
function Write-RepairLog([string]$Line) {
    [IO.File]::AppendAllText($script:LogPath, $Line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

# Use the actual access token, not the availability of the Server service.
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $system = [Environment]::SystemDirectory
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
        $system = Join-Path $env:SystemRoot 'Sysnative'
    }
    if (-not $isAdmin) {
        if ($Elevated) { throw 'Administrator privileges were not granted.' }
        Write-Host 'Administrator rights are required. Confirm the Windows UAC prompt.'
        $ps = Join-Path $system 'WindowsPowerShell\v1.0\powershell.exe'
        # File path is data, never interpolated into an executable PowerShell command.
        $argsLine = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevated' -f $PSCommandPath
        if ($Interactive) { $argsLine += ' -Interactive' }
        if ($Yes) { $argsLine += ' -Yes' }
        $child = Start-Process -FilePath $ps -ArgumentList $argsLine -WorkingDirectory $system -Verb RunAs -PassThru
        $child.WaitForExit()
        exit $child.ExitCode
    }
} catch {
    Write-Host ('WinRep could not start: ' + $_.Exception.Message) -ForegroundColor Red
    Wait-ForUser
    exit 1
}

$mutex = $null; $ownsMutex = $false; $runDir = $null; $script:LogPath = $null; $exitCode = 1
try {
    . (Join-Path $PSScriptRoot 'lib\WinRep.Core.ps1')
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 10240 -or $os.Version -notlike '10.*') {
        throw 'Only Windows 10 and Windows 11 client installations are supported.'
    }
    $dism = Join-Path $system 'dism.exe'
    $sfc = Join-Path $system 'sfc.exe'
    foreach ($exe in @($dism, $sfc)) { if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing Windows tool: $exe" } }
    if ($Interactive) { $Host.UI.RawUI.WindowTitle = 'WinRep 1.3.0' }
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkYellow
    Write-Host '  WinRep 1.3.0 | Windows System Repair' -ForegroundColor Yellow
    Write-Host '  Windows broke it. Windows can fix it.'
    Write-Host '============================================================' -ForegroundColor DarkYellow
    Write-Host '  1. Repair the Windows component store (DISM).'
    Write-Host '  2. Check protected system files (SFC).'
    Write-Host ''
    Write-Host 'This changes Windows system components. Save your work first.'
    Write-Host 'Do not shut down or restart while repair is running.'
    Write-Host 'WinRep does not automatically restart Windows.'
    if (-not $Yes) {
        $answer = Read-Host 'Start repair? [y/N]'
        if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled. No repairs were started.'; exit 0 }
    }
    $mutex = [Threading.Mutex]::new($false, 'Global\WinRep.SystemRepair')
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'Another WinRep session is already running.' }
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
        throw 'The desktop folder is unavailable. No repairs were started.'
    }
    $name = 'WinRep-{0}-{1}' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), ([guid]::NewGuid().ToString('N').Substring(0,12))
    $runDir = Join-Path $desktop $name
    [void][IO.Directory]::CreateDirectory($runDir)
    $script:LogPath = Join-Path $runDir 'Windows_Repair.log'
    $dismLog = Join-Path $runDir 'DISM.log'
    $sfcOut = Join-Path $runDir 'SFC.stdout.bin'
    $sfcErr = Join-Path $runDir 'SFC.stderr.bin'
    [IO.File]::WriteAllText($script:LogPath, "WinRep 1.3.0`r`n", [Text.UTF8Encoding]::new($true))
    Write-RepairLog ('Start: ' + (Get-Date -Format o))
    Write-RepairLog ('OS: {0}; version: {1}; build: {2}' -f $os.Caption, $os.Version, $os.BuildNumber)
    Write-Host "Logs: $runDir"
    Write-Host ''
    Write-Host '[1/2] Repairing the Windows component store (DISM)...' -ForegroundColor Yellow
    Write-Host 'Progress may pause for a while. This is normal.'
    Write-RepairLog ('DISM start: ' + (Get-Date -Format o))
    & $dism /Online /Cleanup-Image /RestoreHealth /English /NoRestart "/LogPath:$dismLog"
    $dismRC = $LASTEXITCODE
    $dismStatus = Get-DismStatus $dismRC
    Write-RepairLog ('DISM: {0}; exit code: {1}; end: {2}' -f $dismStatus, $dismRC, (Get-Date -Format o))
    if ($dismStatus -eq 'ERROR') {
        Write-Host "DISM failed (exit code $dismRC). SFC will still be attempted." -ForegroundColor Yellow
    } elseif ($dismStatus -eq 'OK_REBOOT') {
        Write-Host 'DISM completed and requested a restart.' -ForegroundColor Yellow
    } else { Write-Host 'DISM completed successfully.' -ForegroundColor Green }

    $sfcRC = 0
    if ($dismStatus -eq 'OK_REBOOT') {
        $sfcStatus = 'SKIPPED_REBOOT'
        Write-Host '[2/2] SFC postponed until after restart.' -ForegroundColor Yellow
        Write-RepairLog 'SFC was not executed: DISM requested a restart.'
    } else {
        Write-Host ''
        Write-Host '[2/2] Checking protected system files (SFC)...' -ForegroundColor Yellow
        Write-Host 'Progress is captured in the log. The window may look idle for several minutes.'
        Write-RepairLog ('SFC start: ' + (Get-Date -Format o))
        $proc = [Diagnostics.Process]::new(); $out = $null; $err = $null
        try {
            $proc.StartInfo.FileName = $sfc
            $proc.StartInfo.Arguments = '/scannow'
            $proc.StartInfo.WorkingDirectory = $system
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.CreateNoWindow = $true
            $proc.StartInfo.RedirectStandardOutput = $true
            $proc.StartInfo.RedirectStandardError = $true
            $out = [IO.MemoryStream]::new()
            $err = [IO.MemoryStream]::new()
            if (-not $proc.Start()) { throw 'SFC could not be started.' }
            $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($out)
            $errTask = $proc.StandardError.BaseStream.CopyToAsync($err)
            # Drain both pipes concurrently to prevent output-buffer deadlocks.
            $proc.WaitForExit()
            [void]$outTask.GetAwaiter().GetResult()
            [void]$errTask.GetAwaiter().GetResult()
            $sfcRC = $proc.ExitCode
            [IO.File]::WriteAllBytes($sfcOut, $out.ToArray())
            [IO.File]::WriteAllBytes($sfcErr, $err.ToArray())
        } finally {
            if ($null -ne $out) { $out.Dispose() }
            if ($null -ne $err) { $err.Dispose() }
            $proc.Dispose()
        }
        $oem = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        $stdout = ConvertFrom-NativeBytes ([IO.File]::ReadAllBytes($sfcOut)) $oem
        $stderr = ConvertFrom-NativeBytes ([IO.File]::ReadAllBytes($sfcErr)) $oem
        Write-RepairLog "SFC stdout:`r`n$stdout`r`nSFC stderr:`r`n$stderr"
        $sfcStatus = Get-SfcStatus ($stdout + "`n" + $stderr)
        Write-RepairLog ('SFC: {0}; exit code: {1}; end: {2}' -f $sfcStatus, $sfcRC, (Get-Date -Format o))
    }
    $summary = Get-RepairSummary $dismStatus $sfcStatus $sfcRC
    $exitCode = $summary.ExitCode
    $sfcDescriptions = @{
        CLEAN='No integrity violations found.'; REPAIRED='Corrupted files were repaired.'
        UNREPAIRED='Some corrupted files could not be repaired.'; FAILED='The scan could not complete.'
        REBOOT_REQUIRED='Windows is waiting for a restart.'; SKIPPED_REBOOT='Deferred until after restart.'
        UNKNOWN='Result not recognized; review the log.'
    }
    Write-Host ''
    Write-Host '======================== RESULTS ===========================' -ForegroundColor DarkYellow
    Write-Host "DISM: $dismStatus (exit code $dismRC)"
    if ($sfcStatus -eq 'SKIPPED_REBOOT') { Write-Host 'SFC: Deferred until after restart.' }
    else { Write-Host ('SFC: {0} (exit code {1})' -f $sfcDescriptions[$sfcStatus], $sfcRC) }
    foreach ($note in $summary.Notes) { Write-Host $note; Write-RepairLog $note }
    Write-RepairLog ('WinRep exit code: ' + $exitCode)
    Write-RepairLog ('End: ' + (Get-Date -Format o))
} catch {
    $message = 'WinRep stopped: ' + $_.Exception.Message
    Write-Host $message -ForegroundColor Red
    if ($script:LogPath) { try { Write-RepairLog $message } catch { Write-Host 'Could not write the diagnostic log.' } }
    $exitCode = 1
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
if ($runDir -and (Test-Path -LiteralPath $runDir)) { Write-Host "`nLogs: $runDir" }
if ($Interactive) {
    if ($runDir -and (Test-Path -LiteralPath $runDir)) {
        [void](Read-Host 'Press Enter to open the log folder and close')
        try { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"{0}"' -f $runDir) }
        catch { Write-Host 'Could not open the log folder automatically.'; Wait-ForUser }
    } else { Wait-ForUser }
}
exit $exitCode
