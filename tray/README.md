# a2a tray icon (Windows)

A notification-area icon that shows daemon state at a glance, reading the
heartbeat and activity markers the daemon writes to `~/.a2a`.

| Icon | State |
|------|-------|
| up-chevrons `⌃⌃` (foreground colour) | running, idle |
| right-chevrons `››` (blue) | sending to a peer |
| left-chevrons `‹‹` (green) | receiving from a peer |
| down-chevrons (grey) | daemon down / heartbeat stale |

Direction is the primary signal, colour secondary, so the states stay
distinguishable in greyscale (colour-blind safe). Design: `icons/src/DESIGN.md`
("Two Roofs"). Regenerate the `.ico` sets with `python3 gen_icons.py` (needs
Pillow); it emits a `dark/` and a `light/` set and the tray picks the one that
matches the current taskbar theme.

## Run it

```powershell
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File a2a-tray.ps1
```

The script auto-detects the WSL `~/.a2a` path via `wslpath`. Right-click the
icon for **Show status / Restart daemon / Exit**; double-click shows a status
balloon.

## Auto-start on login

```powershell
powershell -ExecutionPolicy Bypass -File setup-tray.ps1 enable    # add Startup shortcut
powershell -ExecutionPolicy Bypass -File setup-tray.ps1 disable   # remove it
powershell -ExecutionPolicy Bypass -File setup-tray.ps1 status
```
