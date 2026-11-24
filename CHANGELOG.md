# Changelog

## 1.3.0 — Windows needs a little help

- English interface; preserved English and Russian SFC result detection.
- Kept the double-click CMD entry point and moved the implementation into Windows PowerShell 5.1.
- Token-based administrator check and quoted UAC relaunch; explicit interactive confirmation.
- Unique log directories, preserved detailed DISM logs and raw SFC output.
- Concurrent pipe capture and more conservative status classification.
- Separate DISM/SFC recommendations, restart deferral on DISM exit 3010, and explicit result codes.
- Single-instance guard, Windows client check, and native executable resolution.
- MIT license, new documentation, Windows CI and tag-based ZIP releases.

## 1.2 — Original version

- Double-click Windows 10/11 DISM and SFC repair workflow.
- Russian interface, bilingual result matching, desktop logs and reboot recommendations.
