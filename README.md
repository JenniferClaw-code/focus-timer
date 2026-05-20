# Focus Timer

A terminal Pomodoro timer with session history and daily streak tracking.

## How to run

Double-click `Start.bat`, or open PowerShell in this folder and run:

```
powershell -ExecutionPolicy Bypass -File FocusTimer.ps1
```

## Controls

| Key | Action |
|-----|--------|
| Enter | Start the next phase |
| Q | Quit |
| S | Skip the current phase |

## Pomodoro rhythm

- 25 min **focus** → 5 min **short break** (×3)
- 25 min **focus** → 15 min **long break**
- Repeat

## Data

Session history is saved to `sessions.json` in the same folder. Each entry records the date, time, type (work/break), and duration.
