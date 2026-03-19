#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Queries and analyzes your Tempo timesheet data.

.DESCRIPTION
    Retrieves your Tempo worklogs and provides analysis including:
    - Total hours logged for day/week/month
    - Remaining hours needed (based on 40hr work week)
    - Breakdown by ticket
    - Most commonly logged tickets
    - Daily/weekly trends

.PARAMETER Period
    Time period to analyze: Today, ThisWeek, LastWeek, ThisMonth, LastMonth, or Custom

.PARAMETER From
    Start date for custom period (YYYY-MM-DD)

.PARAMETER To
    End date for custom period (YYYY-MM-DD)

.PARAMETER GroupBy
    Group results by: Ticket, Day, Week, or Account

.PARAMETER Top
    Show top N most logged tickets (default: 10)

.PARAMETER ShowRemaining
    Calculate and show remaining hours based on 40hr work week

.EXAMPLE
    ./Get-TempoTimesheet.ps1 -Period Today

.EXAMPLE
    ./Get-TempoTimesheet.ps1 -Period ThisWeek -ShowRemaining

.EXAMPLE
    ./Get-TempoTimesheet.ps1 -Period ThisMonth -GroupBy Ticket -Top 5

.EXAMPLE
    ./Get-TempoTimesheet.ps1 -From "2026-02-01" -To "2026-02-09" -GroupBy Day
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Today', 'ThisWeek', 'LastWeek', 'ThisMonth', 'LastMonth', 'Custom')]
    [string]$Period = 'ThisWeek',
    
    [Parameter(Mandatory=$false)]
    [string]$From,
    
    [Parameter(Mandatory=$false)]
    [string]$To,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Ticket', 'Day', 'Week', 'Account')]
    [string]$GroupBy = 'Ticket',
    
    [Parameter(Mandatory=$false)]
    [int]$Top = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowRemaining
)

# Environment validation
$requiredVars = @{
    'TEMPO_API_TOKEN' = $env:TEMPO_API_TOKEN
    'TEMPO_BASE_URL' = $env:TEMPO_BASE_URL
    'TEMPO_ACCOUNT_ID' = $env:TEMPO_ACCOUNT_ID
    'ATLASSIAN_EMAIL' = $env:ATLASSIAN_EMAIL
    'ATLASSIAN_API_TOKEN' = $env:ATLASSIAN_API_TOKEN
}

foreach ($var in $requiredVars.GetEnumerator()) {
    if ([string]::IsNullOrEmpty($var.Value)) {
        Write-Error "Environment variable $($var.Key) is not set."
        exit 1
    }
}

# Calculate date range
$today = Get-Date

# If From/To are specified, use custom mode
if (![string]::IsNullOrEmpty($From) -or ![string]::IsNullOrEmpty($To)) {
    $Period = 'Custom'
}

switch ($Period) {
    'Today' {
        $From = $today.ToString("yyyy-MM-dd")
        $To = $From
    }
    'ThisWeek' {
        $monday = $today.AddDays(-($today.DayOfWeek.value__ - 1))
        $From = $monday.ToString("yyyy-MM-dd")
        $To = $today.ToString("yyyy-MM-dd")
    }
    'LastWeek' {
        $lastMonday = $today.AddDays(-($today.DayOfWeek.value__ + 6))
        $lastSunday = $lastMonday.AddDays(6)
        $From = $lastMonday.ToString("yyyy-MM-dd")
        $To = $lastSunday.ToString("yyyy-MM-dd")
    }
    'ThisMonth' {
        $From = (Get-Date -Day 1).ToString("yyyy-MM-dd")
        $To = $today.ToString("yyyy-MM-dd")
    }
    'LastMonth' {
        $firstOfThisMonth = Get-Date -Day 1
        $firstOfLastMonth = $firstOfThisMonth.AddMonths(-1)
        $lastOfLastMonth = $firstOfThisMonth.AddDays(-1)
        $From = $firstOfLastMonth.ToString("yyyy-MM-dd")
        $To = $lastOfLastMonth.ToString("yyyy-MM-dd")
    }
    'Custom' {
        if ([string]::IsNullOrEmpty($From) -or [string]::IsNullOrEmpty($To)) {
            Write-Error "Custom period requires -From and -To parameters"
            exit 1
        }
    }
}

Write-Host "`n=== Tempo Timesheet Analysis ===" -ForegroundColor Cyan
Write-Host "Period: $From to $To`n" -ForegroundColor Gray

# Fetch worklogs from Tempo
$tempoUrl = "$env:TEMPO_BASE_URL/worklogs?from=$From&to=$To&limit=1000"
$tempoHeaders = @{
    'Authorization' = "Bearer $env:TEMPO_API_TOKEN"
}

try {
    $response = Invoke-RestMethod -Uri $tempoUrl -Headers $tempoHeaders -Method Get
    
    # Filter to only user's worklogs
    $worklogs = $response.results | Where-Object { $_.author.accountId -eq $env:TEMPO_ACCOUNT_ID }
    
    if ($worklogs.Count -eq 0) {
        Write-Host "No worklogs found for this period." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($worklogs.Count) worklogs`n" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to fetch worklogs: $_"
    exit 1
}

# Get issue keys for all unique issue IDs
$issueMap = @{}
$uniqueIssueIds = $worklogs.issue.id | Select-Object -Unique

Write-Host "Fetching issue details..." -ForegroundColor Gray
$jiraAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${env:ATLASSIAN_EMAIL}:${env:ATLASSIAN_API_TOKEN}"))
$jiraHeaders = @{
    'Authorization' = "Basic $jiraAuth"
    'Accept' = 'application/json'
}

foreach ($issueId in $uniqueIssueIds) {
    try {
        $jiraUrl = "https://relias.atlassian.net/rest/api/2/issue/$issueId`?fields=key,summary"
        $issue = Invoke-RestMethod -Uri $jiraUrl -Headers $jiraHeaders -Method Get
        $issueMap[$issueId] = @{
            Key = $issue.key
            Summary = $issue.fields.summary
        }
    } catch {
        $issueMap[$issueId] = @{
            Key = "UNKNOWN-$issueId"
            Summary = "Unable to fetch"
        }
    }
}

# Calculate totals
$totalSeconds = ($worklogs | Measure-Object -Property timeSpentSeconds -Sum).Sum
$totalHours = [math]::Round($totalSeconds / 3600, 2)

Write-Host "`n--- Summary ---" -ForegroundColor Yellow
Write-Host "Total Hours Logged: $totalHours hours" -ForegroundColor White

# Calculate remaining hours if requested
if ($ShowRemaining) {
    $workDays = 0
    $currentDate = [DateTime]::Parse($From)
    $endDate = [DateTime]::Parse($To)
    
    while ($currentDate -le $endDate) {
        if ($currentDate.DayOfWeek -ne [DayOfWeek]::Saturday -and 
            $currentDate.DayOfWeek -ne [DayOfWeek]::Sunday) {
            $workDays++
        }
        $currentDate = $currentDate.AddDays(1)
    }
    
    $expectedHours = $workDays * 8
    $remaining = $expectedHours - $totalHours
    
    Write-Host "Expected Hours: $expectedHours hours ($workDays work days × 8h)" -ForegroundColor Gray
    if ($remaining -gt 0) {
        Write-Host "Remaining: $remaining hours" -ForegroundColor Red
    } elseif ($remaining -lt 0) {
        Write-Host "Overtime: $([math]::Abs($remaining)) hours" -ForegroundColor Green
    } else {
        Write-Host "Complete! [OK]" -ForegroundColor Green
    }
}

# Group and analyze data
Write-Host "`n--- Breakdown by $GroupBy ---" -ForegroundColor Yellow

switch ($GroupBy) {
    'Ticket' {
        $grouped = $worklogs | Group-Object -Property { $_.issue.id } | ForEach-Object {
            $issueId = $_.Name
            $totalSec = ($_.Group | Measure-Object -Property timeSpentSeconds -Sum).Sum
            $hours = [math]::Round($totalSec / 3600, 2)
            $account = $_.Group[0].attributes.values | Where-Object { $_.key -eq '_Account_' } | Select-Object -ExpandProperty value -First 1
            
            [PSCustomObject]@{
                IssueKey = $issueMap[$issueId].Key
                Summary = $issueMap[$issueId].Summary
                Account = $account
                Hours = $hours
                Entries = $_.Count
                Percentage = [math]::Round(($totalSec / $totalSeconds) * 100, 1)
            }
        } | Sort-Object -Property Hours -Descending | Select-Object -First $Top
        
        $grouped | Format-Table -Property @{
            Label = 'Ticket'
            Expression = { $_.IssueKey }
            Width = 12
        }, @{
            Label = 'Hours'
            Expression = { $_.Hours.ToString("0.00") }
            Width = 8
            Alignment = 'Right'
        }, @{
            Label = 'Entries'
            Expression = { $_.Entries }
            Width = 8
            Alignment = 'Right'
        }, @{
            Label = '%'
            Expression = { "$($_.Percentage)%" }
            Width = 8
            Alignment = 'Right'
        }, @{
            Label = 'Account'
            Expression = { $_.Account }
            Width = 12
        }, @{
            Label = 'Summary'
            Expression = { 
                if ($_.Summary.Length -gt 50) {
                    $_.Summary.Substring(0, 47) + "..."
                } else {
                    $_.Summary
                }
            }
        } -AutoSize
    }
    
    'Day' {
        $grouped = $worklogs | Group-Object -Property startDate | ForEach-Object {
            $totalSec = ($_.Group | Measure-Object -Property timeSpentSeconds -Sum).Sum
            $hours = [math]::Round($totalSec / 3600, 2)
            $date = [DateTime]::Parse($_.Name)
            
            [PSCustomObject]@{
                Date = $date.ToString("yyyy-MM-dd (ddd)")
                Hours = $hours
                Entries = $_.Count
                Status = if ($hours -ge 8) { "[OK]" } elseif ($hours -gt 0) { "[PARTIAL]" } else { "[NONE]" }
            }
        } | Sort-Object -Property Date
        
        $grouped | Format-Table -Property @{
            Label = 'Date'
            Expression = { $_.Date }
            Width = 20
        }, @{
            Label = 'Hours'
            Expression = { $_.Hours.ToString("0.00") }
            Width = 8
            Alignment = 'Right'
        }, @{
            Label = 'Entries'
            Expression = { $_.Entries }
            Width = 8
            Alignment = 'Right'
        }, @{
            Label = 'Status'
            Expression = { $_.Status }
            Width = 8
        } -AutoSize
    }
    
    'Account' {
        $grouped = $worklogs | ForEach-Object {
            $account = $_.attributes.values | Where-Object { $_.key -eq '_Account_' } | Select-Object -ExpandProperty value -First 1
            [PSCustomObject]@{
                Account = $account
                Hours = $_.timeSpentSeconds / 3600
            }
        } | Group-Object -Property Account | ForEach-Object {
            $totalHrs = ($_.Group | Measure-Object -Property Hours -Sum).Sum
            
            [PSCustomObject]@{
                Account = $_.Name
                Hours = [math]::Round($totalHrs, 2)
                Entries = $_.Count
                Percentage = [math]::Round(($totalHrs / $totalHours) * 100, 1)
            }
        } | Sort-Object -Property Hours -Descending
        
        $grouped | Format-Table -Property @{
            Label = 'Account'
            Expression = { $_.Account }
            Width = 15
        }, @{
            Label = 'Hours'
            Expression = { $_.Hours.ToString("0.00") }
            Width = 10
            Alignment = 'Right'
        }, @{
            Label = 'Entries'
            Expression = { $_.Entries }
            Width = 10
            Alignment = 'Right'
        }, @{
            Label = 'Percentage'
            Expression = { "$($_.Percentage)%" }
            Width = 12
            Alignment = 'Right'
        } -AutoSize
    }
}

Write-Host ""
