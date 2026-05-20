#Requires -Version 5.0
<#
  Focus Timer - Pomodoro with session history and daily streak
  Run: powershell -ExecutionPolicy Bypass -File FocusTimer.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Config ------------------------------------------------------------------
$WorkMinutes  = 25
$ShortBreak   = 5
$LongBreak    = 15
$RoundsPerSet = 4
$DataFile     = Join-Path $PSScriptRoot "sessions.json"

# -- Color helper ------------------------------------------------------------
function Write-C([string]$text, [string]$color = "White", [switch]$NoNewline) {
    if ($NoNewline) { Write-Host $text -ForegroundColor $color -NoNewline }
    else            { Write-Host $text -ForegroundColor $color }
}

# -- Data helpers ------------------------------------------------------------
function Load-Sessions {
    if (Test-Path $DataFile) {
        try { return @(Get-Content $DataFile -Raw | ConvertFrom-Json) } catch {}
    }
    return @()
}

function Save-Session([string]$type, [int]$minutes) {
    $sessions = Load-Sessions
    $entry = [PSCustomObject]@{
        date    = (Get-Date).ToString("yyyy-MM-dd")
        time    = (Get-Date).ToString("HH:mm")
        type    = $type
        minutes = $minutes
    }
    $all = @($sessions) + @($entry)
    $all | ConvertTo-Json -Depth 3 | Set-Content $DataFile -Encoding UTF8
}

function Get-Stats {
    $sessions  = Load-Sessions
    $today     = (Get-Date).ToString("yyyy-MM-dd")
    $todayWork = @($sessions | Where-Object { $_.date -eq $today -and $_.type -eq "work" })
    $sumObj    = $todayWork | Measure-Object -Property minutes -Sum
    $todayMins = if ($sumObj.Sum) { [int]$sumObj.Sum } else { 0 }

    # Streak: consecutive days with at least 1 work session, counting back from today
    $streak = 0
    $workSessions = @($sessions | Where-Object { $_.type -eq "work" })
    if ($workSessions.Count -gt 0) {
        $days  = $workSessions | Select-Object -ExpandProperty date -Unique | Sort-Object -Descending
        $check = (Get-Date).Date
        foreach ($d in $days) {
            $dt = [datetime]::ParseExact($d, "yyyy-MM-dd", $null)
            if ($dt.Date -eq $check) {
                $streak++
                $check = $check.AddDays(-1)
            } else { break }
        }
    }

    return @{
        TodaySessions = $todayWork.Count
        TodayMinutes  = $todayMins
        Streak        = $streak
    }
}

# -- UI ----------------------------------------------------------------------
function Draw-Header {
    Clear-Host
    Write-C "+--------------------------------------+" Cyan
    Write-C "|          FOCUS TIMER (tomato)        |" Cyan
    Write-C "+--------------------------------------+" Cyan
    Write-Host ""
}

function Draw-Stats {
    $s = Get-Stats
    $plural = if ($s.Streak -ne 1) { "days" } else { "day" }
    Write-C "  Today:  " DarkGray -NoNewline
    Write-C "$($s.TodaySessions) sessions ($($s.TodayMinutes) min focused)" Yellow
    Write-C "  Streak: " DarkGray -NoNewline
    if ($s.Streak -gt 0) {
        Write-C "$($s.Streak) $plural" Green
    } else {
        Write-C "Start your first session!" Yellow
    }
    Write-Host ""
}

function Format-Countdown([int]$seconds) {
    "{0:D2}:{1:D2}" -f [math]::Floor($seconds / 60), ($seconds % 60)
}

function Draw-ProgressBar([int]$elapsed, [int]$total) {
    $width  = 36
    $pct    = [math]::Min(1.0, $elapsed / $total)
    $filled = [math]::Round($pct * $width)
    $empty  = $width - $filled
    $bar    = ("#" * $filled) + ("-" * $empty)
    $pctStr = "$([math]::Round($pct * 100))%".PadLeft(4)
    Write-C "  [" White -NoNewline
    Write-C $bar Green -NoNewline
    Write-C "] $pctStr" White
}

function Show-Notification([string]$title, [string]$msg) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $balloon.Icon = [System.Drawing.SystemIcons]::Information
        $balloon.BalloonTipTitle = $title
        $balloon.BalloonTipText  = $msg
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(3000)
        Start-Sleep -Milliseconds 200
        $balloon.Dispose()
    } catch { }
}

function Run-Timer([string]$label, [string]$labelColor, [int]$durationMinutes) {
    $totalSec  = $durationMinutes * 60
    $startTime = Get-Date

    while ($true) {
        $elapsed   = [int]((Get-Date) - $startTime).TotalSeconds
        $remaining = [math]::Max(0, $totalSec - $elapsed)

        Draw-Header
        Draw-Stats
        Write-C "  Phase:  $label" $labelColor
        Write-Host ""
        Write-C ("  " + (Format-Countdown $remaining)) White
        Write-Host ""
        Draw-ProgressBar $elapsed $totalSec
        Write-Host ""
        Write-C "  Q = quit   S = skip phase" DarkGray
        Write-Host ""

        if ($remaining -le 0) { return "done" }

        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            if ($key -eq [ConsoleKey]::Q) { return "quit" }
            if ($key -eq [ConsoleKey]::S) { return "skip" }
        }

        Start-Sleep -Milliseconds 500
    }
}

# -- Main --------------------------------------------------------------------
function Main {
    $round = 0

    while ($true) {
        $round++
        $isLongBreak = (($round % $RoundsPerSet) -eq 0)

        Draw-Header
        Draw-Stats
        Write-C "  Round $round  --  Press ENTER to start, Q to quit" Yellow
        $input = Read-Host
        if ($input -eq "q" -or $input -eq "Q") { break }

        # Work phase
        $result = Run-Timer "FOCUS  ($WorkMinutes min)" Green $WorkMinutes
        if ($result -eq "quit") { break }
        if ($result -eq "done") {
            Save-Session "work" $WorkMinutes
            Show-Notification "Focus Timer" "Nice work! Time for a break."
        }

        # Break phase
        $breakLen   = if ($isLongBreak) { $LongBreak } else { $ShortBreak }
        $breakLabel = if ($isLongBreak) { "LONG BREAK ($breakLen min)" } else { "SHORT BREAK ($breakLen min)" }

        Draw-Header
        Draw-Stats
        Write-C "  Round $round complete!" Green
        Write-C "  Press ENTER for break, S to skip break, Q to quit" DarkGray
        $input = Read-Host
        if ($input -eq "q" -or $input -eq "Q") { break }

        if ($input -ne "s" -and $input -ne "S") {
            $result = Run-Timer $breakLabel Cyan $breakLen
            if ($result -eq "quit") { break }
            if ($result -eq "done") {
                Save-Session "break" $breakLen
                Show-Notification "Focus Timer" "Break over -- ready to focus?"
            }
        }
    }

    Draw-Header
    $s = Get-Stats
    Write-C "  Session ended. Great work!" Green
    Write-Host ""
    Write-C "  Today: $($s.TodaySessions) sessions, $($s.TodayMinutes) min focused" Yellow
    $plural = if ($s.Streak -ne 1) { "days" } else { "day" }
    Write-C "  Streak: $($s.Streak) $plural" Cyan
    Write-Host ""
    Write-C "  History saved to: $DataFile" DarkGray
    Write-Host ""
    Write-C "  Press any key to exit..." DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Main
