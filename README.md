# WinRep

*Windows broke it. Windows can fix it.*

![Windows 10 / 11](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=flat-square)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square)
![No installer](https://img.shields.io/badge/installer-not%20needed-d97706?style=flat-square)
![MIT License](https://img.shields.io/badge/license-MIT-555555?style=flat-square)

A tiny Windows repair helper for people who would rather double-click a file than remember two commands. WinRep runs Microsoft's built-in DISM and SFC tools in the right order, explains their results, and saves diagnostic logs.

No installer. No extra runtime. No mysterious registry tweaks.

## Give Windows a little help

1. Download `winrep-v1.3.0.zip` from the [latest release](https://github.com/SashaAkana/winrep/releases/latest).
2. **Extract the entire ZIP** into a folder. Keep `winrep.cmd`, `winrep.ps1` and `lib/` together.
3. Double-click `winrep.cmd`, approve the Windows administrator prompt, and confirm the repair with `y`.
4. Keep the window open until the results appear. Press Enter to open your log folder.

Save your work before starting. The repair may take a while and DISM progress can appear stuck. WinRep never schedules or requests an automatic reboot; if one is needed, the result explains what to do next.

```text
  WinRep 1.3.0 | Windows System Repair
  Windows broke it. Windows can fix it.

  [1/2] Repairing the Windows component store (DISM)...
  [2/2] Checking protected system files (SFC)...

  ======================== RESULTS ===========================
  DISM: OK (exit code 0)
  SFC: No integrity violations found. (exit code 0)
  No further action indicated by these two checks.
```

*Illustrative output, not a promise about your PC.*

## What it actually does

- Runs DISM RestoreHealth, then SFC Scannow (unless DISM requests a restart first).
- Uses an English interface and recognizes common English and Russian SFC outcomes.
- Keeps each run's logs in its own desktop folder.
- Explains failures and restart recommendations separately. Unknown output is never called a success.

Windows 10 or 11 with built-in Windows PowerShell 5.1 and administrator access is required. The native Windows messages may be localized. This is a helper for system-file and component-store repair, **not** an all-purpose PC fixer, malware scanner or hardware diagnostic.

## Under the hood (no magic screwdriver)

- [What happens behind the window](docs/architecture.md)
- [When Windows refuses to cooperate](docs/usage.md)
- [Trust, but do not repair the CI runner](docs/testing.md)
- [Changelog](CHANGELOG.md)

[MIT License](LICENSE).

*Have you tried repairing it before reinstalling it?*
