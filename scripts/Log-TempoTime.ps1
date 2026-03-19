#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Logs time to Tempo via API with standardized ticket/account mapping.

.DESCRIPTION
    Submits time entries to Tempo Timesheets API with automatic mapping of:
    - Shorthand names to Jira ticket keys
    - Ticket keys to Tempo account codes
    - Duration strings to seconds
    - Recurring meetings to default durations

.PARAMETER Ticket
    Ticket key or shorthand (e.g., "infra", "SYS-XXXX", "standup", "1:1")

.PARAMETER Duration
    Time spent (e.g., "2h", "30m", "1.5h", "1h30m"). Optional for recurring meetings.

.PARAMETER Description
    Work description. Auto-generated for recurring meetings if not provided.

.PARAMETER Date
    Date to log time (YYYY-MM-DD). Defaults to today.

.PARAMETER StartTime
    Start time (HH:MM:SS). Defaults to 09:00:00.

.EXAMPLE
    ./Log-TempoTime.ps1 -Ticket "infra" -Duration "6h30m" -Description "Infrastructure work"

.EXAMPLE
    ./Log-TempoTime.ps1 -Ticket "standup"

.EXAMPLE
    ./Log-TempoTime.ps1 -Ticket "1:1" -Date "2026-02-08"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Ticket,
    
    [Parameter(Mandatory=$false)]
    [string]$Duration,
    
    [Parameter(Mandatory=$false)]
    [string]$Description,
    
    [Parameter(Mandatory=$false)]
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    
    [Parameter(Mandatory=$false)]
    [string]$StartTime = "09:00:00",

    [Parameter(Mandatory=$false)]
    [string]$AccountCode,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Get script directory and load configuration
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mappingConfigPath = Join-Path $scriptDir "ticket-mappings.json"

# Validate mapping config file exists
if (-not (Test-Path $mappingConfigPath)) {
    Write-Error "Ticket mapping configuration file not found: $mappingConfigPath"
    Write-Host "Please create this file with your team's ticket mappings. See SKILL.md for setup instructions." -ForegroundColor Yellow
    exit 1
}

# Load ticket mappings configuration
try {
    $mappingConfig = Get-Content $mappingConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to read ticket mapping configuration: $_"
    exit 1
}

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
        Write-Error "Environment variable $($var.Key) is not set. Please configure Tempo API credentials."
        exit 1
    }
}

# Extract mappings from configuration
$ticketMap = @{}
$accountMap = @{}
$recurringMeetings = @{}

# Build mappings from work categories
foreach ($category in $mappingConfig.workCategories.PSObject.Properties) {
    $categoryData = $category.Value
    $jiraTicket = $categoryData.jiraTicket
    $tempoAccount = $categoryData.tempoAccount
    
    # Map each alias to the Jira ticket
    foreach ($alias in $categoryData.aliases) {
        $ticketMap[$alias.ToLower()] = $jiraTicket
    }
    
    # Map the ticket to its Tempo account
    if (-not $accountMap.ContainsKey($jiraTicket)) {
        $accountMap[$jiraTicket] = $tempoAccount
    }
    
    # If this category has defaults, add to recurring meetings for all aliases
    if ($categoryData.defaultDuration -or $categoryData.defaultDescription -or $categoryData.defaultStartTime) {
        foreach ($alias in $categoryData.aliases) {
            $recurringMeetings[$alias.ToLower()] = @{
                Duration = $categoryData.defaultDuration
                Description = $categoryData.defaultDescription
                StartTime = $categoryData.defaultStartTime
            }
        }
    }
}

# Resolve ticket key
$ticketLower = $Ticket.ToLower()
if ($ticketMap.ContainsKey($ticketLower)) {
    $issueKey = $ticketMap[$ticketLower]
    Write-Host "Mapped '$Ticket' → $issueKey" -ForegroundColor Cyan
} else {
    $issueKey = $Ticket.ToUpper()
}

# Check for recurring meeting defaults
if ($recurringMeetings.ContainsKey($ticketLower)) {
    if ([string]::IsNullOrEmpty($Duration)) {
        $Duration = $recurringMeetings[$ticketLower].Duration
        Write-Host "Using default duration for recurring meeting: $Duration" -ForegroundColor Cyan
    }
    if ([string]::IsNullOrEmpty($Description)) {
        $Description = $recurringMeetings[$ticketLower].Description
    }
    if ($StartTime -eq "09:00:00" -and $recurringMeetings[$ticketLower].ContainsKey('StartTime')) {
        $StartTime = $recurringMeetings[$ticketLower].StartTime
        Write-Host "Using default start time for recurring meeting: $StartTime" -ForegroundColor Cyan
    }
}

# Validate duration
if ([string]::IsNullOrEmpty($Duration)) {
    Write-Error "Duration is required. Specify using format like '2h', '30m', or '1h30m'"
    exit 1
}

# Convert duration to seconds
function ConvertTo-Seconds {
    param([string]$Duration)
    
    $totalSeconds = 0
    
    # Match hours
    if ($Duration -match '(\d+\.?\d*)h') {
        $totalSeconds += [decimal]$matches[1] * 3600
    }
    
    # Match minutes
    if ($Duration -match '(\d+\.?\d*)m') {
        $totalSeconds += [decimal]$matches[1] * 60
    }
    
    if ($totalSeconds -eq 0) {
        Write-Error "Invalid duration format: $Duration. Use format like '2h', '30m', or '1h30m'"
        exit 1
    }
    
    return [int]$totalSeconds
}

$timeSpentSeconds = ConvertTo-Seconds -Duration $Duration

# Get account code
if ([string]::IsNullOrEmpty($AccountCode)) {
    if (-not $accountMap.ContainsKey($issueKey)) {
        Write-Error "No account mapping found for $issueKey. Please update the script."
        exit 1
    }
    $accountCode = $accountMap[$issueKey]
} else {
    $accountCode = $AccountCode
}

Write-Host "\nSubmitting worklog:" -ForegroundColor Yellow
Write-Host "  Issue:    $issueKey" -ForegroundColor White
Write-Host "  Duration: $Duration ($timeSpentSeconds seconds)" -ForegroundColor White
Write-Host "  Date:     $Date" -ForegroundColor White
Write-Host "  Account:  $accountCode" -ForegroundColor White
if ($Description) {
    Write-Host "  Desc:     $Description" -ForegroundColor White
}

if ($WhatIf) {
    Write-Host "\n[WHATIF MODE - No worklog submitted]" -ForegroundColor Yellow
    Write-Host "Would submit worklog for issue $issueKey with account $accountCode" -ForegroundColor Yellow
    return $null
}

# Get issue ID from Jira
$jiraUrl = "https://relias.atlassian.net/rest/api/2/issue/$issueKey"
$jiraAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${env:ATLASSIAN_EMAIL}:${env:ATLASSIAN_API_TOKEN}"))
$jiraHeaders = @{
    'Authorization' = "Basic $jiraAuth"
    'Accept' = 'application/json'
}

try {
    $jiraResponse = Invoke-RestMethod -Uri "$jiraUrl`?fields=id" -Headers $jiraHeaders -Method Get
    $issueId = $jiraResponse.id
    Write-Host "  Issue ID: $issueId" -ForegroundColor Gray
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    switch ($statusCode) {
        401 { Write-Error "Jira authentication failed (401). Check ATLASSIAN_EMAIL and ATLASSIAN_API_TOKEN are correct and not expired." }
        403 { Write-Error "Jira access denied (403) for $issueKey. Check your permissions for this project." }
        404 { Write-Error "Issue $issueKey not found (404). Verify the ticket key exists in Jira." }
        default { Write-Error "Failed to get issue ID for $issueKey (HTTP $statusCode): $($_.Exception.Message)" }
    }
    exit 1
}

# Submit to Tempo
$tempoUrl = "$env:TEMPO_BASE_URL/worklogs"
$tempoHeaders = @{
    'Authorization' = "Bearer $env:TEMPO_API_TOKEN"
    'Content-Type' = 'application/json'
}

$body = @{
    issueId = [int]$issueId
    timeSpentSeconds = $timeSpentSeconds
    startDate = $Date
    startTime = $StartTime
    authorAccountId = $env:TEMPO_ACCOUNT_ID
    attributes = @(
        @{
            key = '_Account_'
            value = $accountCode
        }
    )
}

if ($Description) {
    $body.description = $Description
}

$bodyJson = $body | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod -Uri $tempoUrl -Headers $tempoHeaders -Method Post -Body $bodyJson
    
    Write-Host "`n✓ Successfully logged time!" -ForegroundColor Green
    Write-Host "  Worklog ID: #$($response.tempoWorklogId)" -ForegroundColor Green
    Write-Host "  Logged:     $Duration to $issueKey ($accountCode) on $Date" -ForegroundColor Green
    
    return $response
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorBody = $_.ErrorDetails.Message
    if (-not $errorBody -and $_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
        } catch { }
    }
    
    switch ($statusCode) {
        400 { Write-Error "Tempo rejected the request (400 Bad Request). Response: $errorBody" }
        401 { Write-Error "Tempo authentication failed (401). Check TEMPO_API_TOKEN is correct and not expired." }
        403 { Write-Error "Tempo access denied (403). Check TEMPO_ACCOUNT_ID matches the token owner. Current: $($env:TEMPO_ACCOUNT_ID). Response: $errorBody" }
        default { Write-Error "Failed to submit worklog (HTTP $statusCode): $errorBody" }
    }
    exit 1
}
