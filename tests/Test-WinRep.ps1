$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\WinRep.Core.ps1')
$script:count = 0
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -cne $Expected) { throw "$Name expected [$Expected], got [$Actual]" }
    $script:count++
    Write-Host "PASS: $Name"
}
foreach ($relative in @('winrep.ps1', 'lib\WinRep.Core.ps1', 'tests\Test-WinRep.ps1')) {
    $tokens = $null; $errorsFound = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$errorsFound)
    Assert-Equal $errorsFound.Count 0 "Parse $relative"
}
$cases = @(
    @('CLEAN', 'Windows Resource Protection did not find any integrity violations.'),
    @('REPAIRED', 'Windows Resource Protection found corrupt files and successfully repaired them.'),
    @('UNREPAIRED', 'Windows Resource Protection found corrupt files but was unable to fix some of them.'),
    @('FAILED', 'Windows Resource Protection could not perform the requested operation.'),
    @('FAILED', 'Windows Resource Protection could not start the repair service.'),
    @('REBOOT_REQUIRED', 'There is a system repair pending which requires reboot to complete. Restart Windows and run sfc again.'),
    @('CLEAN', 'Защита ресурсов Windows не обнаружила нарушений целостности.'),
    @('REPAIRED', "Защита ресурсов Windows обнаружила повреждённые файлы и успешно`r`nих восстановила."),
    @('REPAIRED', 'Защита ресурсов Windows обнаружила поврежденные файлы и успешно восстановила их.'),
    @('UNREPAIRED', 'Защита ресурсов Windows обнаружила поврежденные файлы, но не может восстановить некоторые из них.'),
    @('FAILED', 'Защите ресурсов Windows не удается выполнить запрошенную операцию.'),
    @('REBOOT_REQUIRED', 'Для завершения восстановления системы требуется перезагрузка.'),
    @('UNKNOWN', 'Verification 100% complete.'),
    @('UNKNOWN', ''),
    @('UNKNOWN', 'Windows Resource Protection did not find any integrity violations. Windows Resource Protection found corrupt files but was unable to fix some of them.')
)
$i = 0
foreach ($case in $cases) {
    $i++
    Assert-Equal (Get-SfcStatus $case[1]) $case[0] "SFC case $i"
}
$ru = 'Защита ресурсов Windows не обнаружила нарушений целостности.'
$en = 'Windows Resource Protection did not find any integrity violations.'
Assert-Equal (ConvertFrom-NativeBytes ([Text.Encoding]::Unicode.GetBytes($ru))) $ru 'UTF-16LE no BOM Russian'
Assert-Equal (ConvertFrom-NativeBytes ([Text.Encoding]::Unicode.GetBytes($en))) $en 'UTF-16LE no BOM English'
Assert-Equal (ConvertFrom-NativeBytes ([byte[]](@(255,254) + [Text.Encoding]::Unicode.GetBytes($ru)))) $ru 'UTF-16LE BOM'
Assert-Equal (ConvertFrom-NativeBytes ([byte[]](@(254,255) + [Text.Encoding]::BigEndianUnicode.GetBytes($ru)))) $ru 'UTF-16BE BOM'
Assert-Equal (ConvertFrom-NativeBytes ([Text.Encoding]::UTF8.GetBytes($ru))) $ru 'UTF-8 no BOM'
Assert-Equal (ConvertFrom-NativeBytes ([byte[]](@(239,187,191) + [Text.Encoding]::UTF8.GetBytes($ru)))) $ru 'UTF-8 BOM'
Assert-Equal (ConvertFrom-NativeBytes ([Text.Encoding]::GetEncoding(866).GetBytes($ru)) 866) $ru 'OEM Cyrillic'
Assert-Equal (ConvertFrom-NativeBytes ([byte[]]@())) '' 'Empty output'
Assert-Equal (Get-DismStatus 0) 'OK' 'DISM success'
Assert-Equal (Get-DismStatus 3010) 'OK_REBOOT' 'DISM restart'
Assert-Equal (Get-DismStatus 87) 'ERROR' 'DISM failure'
$summaryCases = @(
    @('OK','CLEAN',0,0), @('OK','REPAIRED',0,6), @('OK','REBOOT_REQUIRED',1,6),
    @('OK','UNREPAIRED',1,2), @('OK','FAILED',1,3), @('OK','UNKNOWN',0,4),
    @('OK','CLEAN',1,4), @('ERROR','CLEAN',0,5), @('ERROR','REPAIRED',0,5),
    @('ERROR','REBOOT_REQUIRED',1,5), @('OK_REBOOT','SKIPPED_REBOOT',0,6)
)
foreach ($case in $summaryCases) {
    $summary = Get-RepairSummary $case[0] $case[1] $case[2]
    Assert-Equal $summary.ExitCode $case[3] "Summary $($case[0])/$($case[1])/$($case[2])"
}
$summary = Get-RepairSummary 'ERROR' 'REPAIRED' 0
Assert-Equal $summary.Notes.Count 2 'Report DISM failure and restart independently'
$summary = Get-RepairSummary 'ERROR' 'CLEAN' 0
Assert-Equal ($summary.Notes -join ' ' -match 'No further action') $false 'No false reassurance'
$summary = Get-RepairSummary 'OK' 'CLEAN' 0
Assert-Equal ($summary.Notes -join ' ' -match 'No further action') $true 'Clean recommendation'
# Help must never start repair or ask for elevation.
$ps = Join-Path $PSHOME 'powershell.exe'
$helpText = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'winrep.ps1') -Help
Assert-Equal $LASTEXITCODE 0 'Help exit code'
Assert-Equal (($helpText -join ' ') -match 'WinRep 1.3.0') $true 'Help text'
Write-Host "$script:count checks passed. No repair commands were executed."
