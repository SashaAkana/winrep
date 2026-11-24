# Pure helpers. SFC status text may be localized; WinRep's own UI is English.
function ConvertFrom-NativeBytes {
    param([byte[]]$Bytes, [int]$FallbackCodePage = 437)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
    $n = $Bytes.Length
    if ($n -ge 2 -and $Bytes[0] -eq 255 -and $Bytes[1] -eq 254) {
        return [Text.Encoding]::Unicode.GetString($Bytes, 2, $n - 2)
    }
    if ($n -ge 2 -and $Bytes[0] -eq 254 -and $Bytes[1] -eq 255) {
        return [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $n - 2)
    }
    if ($n -ge 3 -and $Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191) {
        return [Text.Encoding]::UTF8.GetString($Bytes, 3, $n - 3)
    }
    # Redirected SFC normally emits UTF-16LE without a BOM. ASCII and Cyrillic
    # have high bytes of 0x00 and 0x04 respectively.
    if ($n % 2 -eq 0) {
        $high = 0; $even = 0
        for ($i = 1; $i -lt [Math]::Min($n, 8192); $i += 2) {
            if ($Bytes[$i] -eq 0 -or $Bytes[$i] -eq 4) { $high++ }
            if ($Bytes[$i-1] -eq 0 -or $Bytes[$i-1] -eq 4) { $even++ }
        }
        if ($high -gt ([Math]::Min($n, 8192) / 4) -and $high -gt $even) {
            return [Text.Encoding]::Unicode.GetString($Bytes)
        }
    }
    try { return ([Text.UTF8Encoding]::new($false, $true)).GetString($Bytes) }
    catch { return [Text.Encoding]::GetEncoding($FallbackCodePage).GetString($Bytes) }
}

function Get-SfcStatus {
    param([AllowEmptyString()][string]$Text)
    $t = ($Text -replace '\x00', '' -replace '[ёЁ]', 'е' -replace '\s+', ' ').Trim()
    $patterns = [ordered]@{
        REBOOT_REQUIRED = 'system repair pending.*?requires (?:a )?reboot|restart windows and run sfc again|для завершения восстановления системы требуется перезагрузка|необходимо перезагрузить.*?sfc|ожидается восстановление системы.*?перезагруз'
        CLEAN = 'did not find any integrity violations|не обнаружила нарушений целостности'
        REPAIRED = 'found corrupt files and successfully repaired them|обнаружила поврежденные файлы и успешно (?:их восстановила|восстановила их|восстановила)'
        UNREPAIRED = 'found corrupt files but was unable to fix some of them|обнаружила поврежденные файлы,? но не может восстановить некоторые из них|не удалось восстановить некоторые из них'
        FAILED = 'could not perform the requested operation|could not start the repair service|не удается выполнить запрошенную операцию|не удалось выполнить запрошенную операцию|не удается запустить службу восстановления|не удалось запустить службу восстановления'
    }
    $matchesFound = @($patterns.Keys | Where-Object { $t -match $patterns[$_] })
    if ($matchesFound.Count -eq 1) { return [string]$matchesFound[0] }
    return 'UNKNOWN'
}

function Get-DismStatus {
    param([int]$ExitCode)
    switch ($ExitCode) { 0 { 'OK' } 3010 { 'OK_REBOOT' } default { 'ERROR' } }
}

function Get-RepairSummary {
    param([string]$DismStatus, [string]$SfcStatus, [int]$SfcExitCode = 0)
    $notes = @()
    if ($DismStatus -eq 'ERROR') { $notes += 'DISM failed. Review the DISM log or ask a technician for help.' }
    if ($DismStatus -eq 'OK_REBOOT' -or $SfcStatus -in @('REPAIRED','REBOOT_REQUIRED','SKIPPED_REBOOT')) {
        $notes += 'Restart Windows when convenient, then run WinRep again.'
    }
    switch ($SfcStatus) {
        'UNREPAIRED' { $notes += 'Some files could not be repaired. Restart, retry and seek help if the issue persists.' }
        'FAILED' { $notes += 'SFC could not complete. Restart and retry; review the log if it fails again.' }
        'UNKNOWN' { $notes += 'SFC output was not recognized. Review the original output in the log.' }
        'CLEAN' { if ($SfcExitCode -ne 0) { $notes += 'SFC reported clean files but returned a non-zero exit code. Review the log.' } }
    }
    if ($DismStatus -eq 'ERROR') { $code = 5 }
    elseif ($SfcStatus -eq 'UNREPAIRED') { $code = 2 }
    elseif ($SfcStatus -eq 'FAILED') { $code = 3 }
    elseif ($SfcStatus -eq 'UNKNOWN' -or ($SfcStatus -eq 'CLEAN' -and $SfcExitCode -ne 0)) { $code = 4 }
    elseif ($DismStatus -eq 'OK_REBOOT' -or $SfcStatus -in @('REPAIRED','REBOOT_REQUIRED','SKIPPED_REBOOT')) { $code = 6 }
    elseif ($DismStatus -eq 'OK' -and $SfcStatus -eq 'CLEAN' -and $SfcExitCode -eq 0) {
        $code = 0; $notes += 'No further action indicated by these two checks.'
    } else { $code = 4; $notes += 'Unexpected result. Review the log.' }
    [pscustomobject]@{ ExitCode = $code; Notes = $notes }
}
