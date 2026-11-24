# When Windows refuses to cooperate

## Before you click

Use a trusted copy on Windows 10/11. Extract all files together. Save open work, have a suitable backup of important files, and avoid running Windows Update or another repair utility at the same time. Use an administrator account or ask a trusted administrator. DISM can require network access or a repair source. A repair may take many minutes; apparent inactivity does not mean it has frozen.

The interactive launcher asks before changing anything. Cancel UAC or answer anything other than `y`/`yes` to cancel. The tool does not restart the PC. Do not close the window or force a shutdown mid-repair.

## Read the result, not the tea leaves

| DISM / SFC result | What it means |
| --- | --- |
| DISM OK, SFC CLEAN | Neither check reports an outstanding problem (not a guarantee of overall PC health). |
| DISM OK_REBOOT | Restart manually; SFC is deferred to the next run. |
| SFC REPAIRED | SFC reports repairs; restart and run WinRep again to verify. |
| SFC REBOOT_REQUIRED | Windows reports a pending repair; restart and retry. |
| SFC UNREPAIRED | Some files remain damaged; restart and retry, seek assistance if persistent. |
| SFC FAILED | The operation could not complete; examine the log and retry after restart. |
| SFC UNKNOWN | The output could not be classified. Read the log, do not assume success. |
| DISM ERROR | Component-store repair failed; review DISM.log even if SFC reports clean files. |

WinRep does not delete CBS logs, reset Windows Update, disable security features, choose a custom ISO, reinstall Windows or fix hardware issues. For ongoing failures, refer to [Microsoft's repair guidance](https://support.microsoft.com/en-us/windows/experience/backup-recovery/use-the-system-file-checker-tool-to-repair-missing-or-corrupted-system-files) or seek assistance.

## The paper trail

A unique `WinRep-YYYY-MM-DD_HH-mm-ss-<id>` folder is created on the desktop of the account running repairs. Press Enter at the end to open it. It contains `Windows_Repair.log` (UTF-8), `DISM.log` if DISM produced one, and `SFC.stdout.bin`/`SFC.stderr.bin` when SFC capture completes. If SFC was deferred there are no SFC files. WinRep retains logs, including successful runs. They may include private paths or device information; inspect them before sending them to anyone.

## Command line (for technicians)

From a trusted extracted directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\winrep.ps1 -Help
```

Help does not elevate or repair. Running `winrep.ps1` directly still asks for confirmation. An administrator can explicitly supply `-Yes` to skip the repair confirmation; elevation is still required. Use `-Interactive` for the launcher-style final prompt and log-folder opening. Execution-policy bypass is scoped to the child process, and does not override enforced Group Policy. This is not a background service.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Clean result, or user cancelled at confirmation before starting. |
| 1 | Setup, elevation or runtime failure. |
| 2 | SFC found damage it could not fully repair. |
| 3 | SFC failed. |
| 4 | Unrecognized, inconsistent or unexpected result. |
| 5 | DISM failed (takes precedence over SFC outcomes). |
| 6 | Restart recommended or required. |

A non-zero exit code is not always a failure: 6 indicates a restart recommendation. Review both tool statuses and original exit codes in the log.
