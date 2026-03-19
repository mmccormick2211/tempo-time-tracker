#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Logs a standard day's worth of time entries to Tempo based on day of week.

.DESCRIPTION
    Reads the standard-day-config.json file and submits all time entries
    for the specified day at once. Automatically determines the correct
    meetings and work blocks based on the day of the week.

.PARAMETER Date
    Date to log time for (YYYY-MM-DD). Defaults to today.
    Day of week is determined from this date.

.PARAMETER DayOfWeek
    Override the day of week (Monday, Tuesday, Wednesday, Thursday, Friday).
    Useful if you want to log a different day's template on a specific date.

.PARAMETER WhatIf
    Show what would be logged without actually submitting to Tempo.

.EXAMPLE
    ./Log-StandardDay.ps1
    # Logs today's standard day based on current day of week

.EXAMPLE
    ./Log-StandardDay.ps1 -Date "2026-02-07"
    # Logs standard day for Friday, February 7, 2026

.EXAMPLE
    ./Log-StandardDay.ps1 -DayOfWeek "Tuesday" -Date "2026-02-10"
    # Logs Tuesday's template for February 10, 2026

.EXAMPLE
    ./Log-StandardDay.ps1 -WhatIf
    # Shows what would be logged without submitting
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")]
    [string]$DayOfWeek,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "standard-day-config.json"
$mappingConfigPath = Join-Path $scriptDir "ticket-mappings.json"
$logScriptPath = Join-Path $scriptDir "Log-TempoTime.ps1"

# Validate config files exist
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

if (-not (Test-Path $mappingConfigPath)) {
    Write-Error "Ticket mapping configuration file not found: $mappingConfigPath"
    Write-Host "Please create this file with your team's ticket mappings. See SKILL.md for setup instructions." -ForegroundColor Yellow
    exit 1
}

# Validate Log-TempoTime.ps1 exists
if (-not (Test-Path $logScriptPath)) {
    Write-Error "Log-TempoTime.ps1 script not found: $logScriptPath"
    exit 1
}

# Read configurations
try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $mappingConfig = Get-Content $mappingConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to read configuration files: $_"
    exit 1
}

# Determine day of week
if (-not $DayOfWeek) {
    $dateObj = [DateTime]::Parse($Date)
    $DayOfWeek = $dateObj.DayOfWeek.ToString()
}

function Test-EntryAppliesToDate {
    param(
        [Parameter(Mandatory=$true)]
        $Entry,

        [Parameter(Mandatory=$true)]
        [DateTime]$DateObj
    )

    if (-not $Entry.PSObject.Properties.Name.Contains('recurrence') -or -not $Entry.recurrence) {
        return $true
    }

    $recurrenceType = $Entry.recurrence.type

    switch ($recurrenceType) {
        "weekly" {
            return $true
        }
        "biweekly" {
            if (-not $Entry.recurrence.anchorDate) {
                Write-Warning "Entry '$($Entry.description)' has biweekly recurrence without anchorDate. Skipping entry."
                return $false
            }

            try {
                $anchorDate = [DateTime]::Parse($Entry.recurrence.anchorDate)
            } catch {
                Write-Warning "Entry '$($Entry.description)' has invalid anchorDate '$($Entry.recurrence.anchorDate)'. Skipping entry."
                return $false
            }

            if ($DateObj.Date -lt $anchorDate.Date) {
                return $false
            }

            $daysSinceAnchor = ($DateObj.Date - $anchorDate.Date).Days
            return (($daysSinceAnchor % 14) -eq 0)
        }
        default {
            Write-Warning "Entry '$($Entry.description)' has unsupported recurrence type '$recurrenceType'. Including entry by default."
            return $true
        }
    }
}

function Get-EntryTicketForDate {
    param(
        [Parameter(Mandatory=$true)]
        $Entry,

        [Parameter(Mandatory=$true)]
        [string]$Date
    )

    if ($Entry.PSObject.Properties.Name.Contains('ticketOverrides') -and $Entry.ticketOverrides) {
        if ($Entry.ticketOverrides.PSObject.Properties.Name.Contains($Date)) {
            return $Entry.ticketOverrides.$Date
        }
    }

    return $Entry.ticket
}

function Get-EntryAccountCode {
    param(
        [Parameter(Mandatory=$true)]
        $Entry,

        [Parameter(Mandatory=$true)]
        $MappingConfig
    )

    if (-not $Entry.PSObject.Properties.Name.Contains('workCategory')) {
        return $null
    }

    if (-not $Entry.workCategory) {
        return $null
    }

    if ($MappingConfig.workCategories.PSObject.Properties.Name.Contains($Entry.workCategory)) {
        return $MappingConfig.workCategories.$($Entry.workCategory).tempoAccount
    }

    return $null
}

# Validate it's a weekday
if ($DayOfWeek -notin @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")) {
    Write-Error "Standard day templates only exist for weekdays. Day of week: $DayOfWeek"
    exit 1
}

# Get standard day entries
if (-not $config.standardDays.PSObject.Properties.Name.Contains($DayOfWeek)) {
    Write-Error "No standard day configuration found for $DayOfWeek"
    exit 1
}

$entries = @($config.standardDays.$DayOfWeek)
$entries = @($entries | Where-Object { Test-EntryAppliesToDate -Entry $_ -DateObj $dateObj })
$expectedTotal = $config.totalHours.$DayOfWeek

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Standard $DayOfWeek - $Date" -ForegroundColor Cyan
Write-Host "  Expected Total: $expectedTotal" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "WhatIf Mode - No time will be logged`n" -ForegroundColor Yellow
}

$results = @()
$totalSeconds = 0

foreach ($entry in $entries) {
    $resolvedTicket = Get-EntryTicketForDate -Entry $entry -Date $Date
    $resolvedAccountCode = Get-EntryAccountCode -Entry $entry -MappingConfig $mappingConfig

    Write-Host "Entry: $($entry.duration) → $resolvedTicket" -ForegroundColor White
    Write-Host "  Description: $($entry.description)" -ForegroundColor Gray
    Write-Host "  Start Time: $($entry.startTime)" -ForegroundColor Gray
    
    if ($WhatIf) {
        Write-Host "  [SKIPPED - WhatIf Mode]`n" -ForegroundColor Yellow
        continue
    }
    
    # Build parameters for Log-TempoTime.ps1
    $params = @{
        Ticket = $resolvedTicket
        Duration = $entry.duration
        Date = $Date
        StartTime = $entry.startTime
    }

    if ($resolvedAccountCode) {
        $params.AccountCode = $resolvedAccountCode
    }
    
    if ($entry.description) {
        $params.Description = $entry.description
    }
    
    try {
        # Call Log-TempoTime.ps1
        $result = & $logScriptPath @params
        
        if ($result) {
            $results += $result
            $totalSeconds += $result.timeSpentSeconds
            Write-Host "  [OK] Logged (Worklog #$($result.tempoWorklogId))`n" -ForegroundColor Green
        }
    } catch {
        Write-Error "Failed to log entry for ${resolvedTicket}: $_"
        Write-Host ""
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "WhatIf Mode - No entries were submitted" -ForegroundColor Yellow
    Write-Host "Total entries that would be logged: $($entries.Count)" -ForegroundColor White
} else {
    $totalHours = [math]::Round($totalSeconds / 3600, 2)
    Write-Host "Entries logged: $($results.Count) of $($entries.Count)" -ForegroundColor White
    Write-Host "Total time: $totalHours hours" -ForegroundColor White
    Write-Host "Expected: $expectedTotal" -ForegroundColor Gray
    
    if ($results.Count -eq $entries.Count) {
        Write-Host "`n[OK] All entries successfully logged!" -ForegroundColor Green
    } else {
        Write-Host "`n[WARN] Some entries failed to log" -ForegroundColor Yellow
    }
}

Write-Host ""
