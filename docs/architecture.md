# What happens behind the window

WinRep is a small wrapper around the Windows servicing tools, not a new servicing engine. It never directly modifies protected files, registry settings, drivers or Windows Update settings.

## The double-click contract

`winrep.cmd` is a minimal launcher for the Windows PowerShell 5.1 executable under the Windows system directory. It uses a process-scoped execution-policy bypass for this particular local script, not a permanent machine policy change. It does not bypass UAC or organizational security controls. Only run a trusted copy. The launcher prefers the native system directory when invoked by a 32-bit process on 64-bit Windows.

`winrep.ps1` checks the actual Windows administrator token. If necessary, it requests elevation with `Start-Process -Verb RunAs` and passes the script path as a quoted file argument, not an interpolated executable command. The elevated process rechecks its token. UAC cancellation stops the tool. It detects Windows client systems through `Win32_OperatingSystem`, then asks for confirmation unless a technician explicitly passes `-Yes`. A named mutex prevents overlapping WinRep repairs on the same machine; it cannot prevent another unrelated servicing tool from running.

`lib/WinRep.Core.ps1` contains output decoding, status matching and summary logic. It has no repair side effects and can be tested without elevation.

## The two-step dance

```text
Launch -> check token -> UAC if needed -> OS check -> confirmation
  -> acquire mutex -> create log directory -> DISM RestoreHealth
       | exit 3010: defer SFC and recommend restart
       | exit 0: run SFC
       | other: record DISM failure, still attempt SFC
  -> decode SFC output -> classify -> report both results -> release mutex
```

Native commands (resolved via the system directory):

```cmd
dism.exe /Online /Cleanup-Image /RestoreHealth /English /NoRestart /LogPath:<run-directory>\DISM.log
sfc.exe /scannow
```

Microsoft recommends repairing the component store first, so SFC can use healthy component files. DISM can contact Windows Update or an organization-configured source; WinRep does not override repair-source policy or supply alternate media. It requests `/NoRestart` and does not invoke shutdown or reboot commands. A DISM failure does not prevent collecting SFC results, but it remains a failure in the final result.

References: [Microsoft repair guidance](https://support.microsoft.com/en-us/windows/experience/backup-recovery/use-the-system-file-checker-tool-to-repair-missing-or-corrupted-system-files), [DISM global options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-global-options-for-command-line-syntax?view=windows-11).

## Listening to SFC without losing the message

SFC's stdout and stderr are captured concurrently as bytes with .NET streams. They are saved separately, decoded, and appended to the UTF-8 main log. The decoder recognizes UTF-16 byte-order marks, typical BOM-less UTF-16LE English/Cyrillic output, UTF-8 and a fallback OEM code page. This is a heuristic for expected native output, not a general encoding detector. The original bytes are retained for troubleshooting.

Whitespace is normalized and Cyrillic `ё` is accepted as `е` for matching. Common English and Russian messages map to `CLEAN`, `REPAIRED`, `UNREPAIRED`, `FAILED`, or `REBOOT_REQUIRED`. Empty, conflicting and unfamiliar messages map to `UNKNOWN`. Other locales may need manual review. Native exit codes are always kept; SFC exit code alone is not a reliable classification contract. A clean message with a non-zero exit code is treated as needing review.

## Privacy and failure behavior

Each run gets a timestamp plus random suffix. Logging must be initialized successfully before repairs begin. Detailed DISM logs and raw SFC streams remain available rather than being deleted during failure handling. No network upload or telemetry is performed by WinRep; Windows servicing itself may access configured update services. Logs can contain computer-specific details, paths and servicing information. Review before sharing. If elevation uses a different administrator account, the desktop and logs belong to that account.
