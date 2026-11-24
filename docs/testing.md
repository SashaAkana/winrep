# Trust, but do not repair the CI runner

WinRep has no third-party runtime or test dependencies. Its test suite checks parsing, result classification, native byte decoding, summary precedence, and the no-side-effect help path. It never executes DISM or SFC, elevates, or modifies Windows system files.

From the repository root on Windows, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-WinRep.ps1
```

GitHub Actions runs the same checks in Windows PowerShell 5.1. A version tag triggers packaging and release publication only after the checks pass. The release ZIP contains the launcher, helper scripts, documentation and MIT license; `SHA256SUMS.txt` accompanies it. The ZIP is the runnable distribution, not a compiled executable. Download and extract it rather than opening the launcher from inside an archive viewer.

## Manual acceptance (disposable Windows VM only)

Take a snapshot of a Windows 10 or 11 VM. Use a healthy installation; do not deliberately corrupt system files.

1. Extract to a folder containing spaces and an apostrophe. Double-click `winrep.cmd`; cancel UAC and confirm no repair starts.
2. Start again, approve UAC, answer `n`; confirm no repair starts.
3. Start again and answer `y`. Check DISM progress, SFC completion, the English summary and log folder opening.
4. Inspect the DISM and SFC logs and compare the native results to the summary.
5. Repeat on English and Russian Windows, check a redirected/OneDrive desktop if available, and check execution when launched from an elevated console.
6. While a run is active, start another and verify that WinRep refuses overlapping repairs. Do not force-stop an ongoing repair.

Restart manually only when needed. CI is intentionally not evidence of successful real Windows servicing; record VM checks separately.
