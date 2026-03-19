#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates Tempo Time Tracker configuration files.

.DESCRIPTION
    Checks that all configuration files are properly formatted and contain required settings.
    Validates ticket mappings, account codes, and standard day configurations.

.EXAMPLE
    ./scripts/Validate-Configuration.ps1
#>

param()

Write-Host "`n=== Tempo Time Tracker Configuration Validation ===" -ForegroundColor Cyan

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mappingConfigPath = Join-Path $scriptDir "ticket-mappings.json"
$standardDayConfigPath = Join-Path $scriptDir "standard-day-config.json"

$validationErrors = @()
$warnings = @()

# Check if files exist
Write-Host "`n1. Checking configuration files exist..." -ForegroundColor Yellow

if (-not (Test-Path $mappingConfigPath)) {
    $validationErrors += "❌ Missing: scripts/ticket-mappings.json - Please ensure this file exists and is properly configured"
} else {
    Write-Host "  ✓ Found: scripts/ticket-mappings.json" -ForegroundColor Green
}

if (-not (Test-Path $standardDayConfigPath)) {
    $validationErrors += "❌ Missing: scripts/standard-day-config.json"
} else {
    Write-Host "  ✓ Found: scripts/standard-day-config.json" -ForegroundColor Green
}

# Validate JSON format
Write-Host "`n2. Validating JSON format..." -ForegroundColor Yellow

if (Test-Path $mappingConfigPath) {
    try {
        $mappingConfig = Get-Content $mappingConfigPath -Raw | ConvertFrom-Json
        Write-Host "  ✓ ticket-mappings.json is valid JSON" -ForegroundColor Green
    } catch {
        $validationErrors += "❌ ticket-mappings.json contains invalid JSON: $_"
    }
}

if (Test-Path $standardDayConfigPath) {
    try {
        $standardDayConfig = Get-Content $standardDayConfigPath -Raw | ConvertFrom-Json
        Write-Host "  ✓ standard-day-config.json is valid JSON" -ForegroundColor Green
    } catch {
        $validationErrors += "❌ standard-day-config.json contains invalid JSON: $_"
    }
}

# Validate ticket mappings structure
if ($mappingConfig) {
    Write-Host "`n3. Validating ticket mappings structure..." -ForegroundColor Yellow
    
    if (-not $mappingConfig.workCategories) {
        $validationErrors += "❌ Missing workCategories section in ticket-mappings.json"
    } else {
        $categoryCount = ($mappingConfig.workCategories | Get-Member -MemberType NoteProperty).Count
        $totalAliases = 0
        $issueKeys = @()
        
        foreach ($category in $mappingConfig.workCategories.PSObject.Properties) {
            $categoryData = $category.Value
            
            # Count aliases
            if ($categoryData.aliases) {
                $totalAliases += $categoryData.aliases.Count
                $issueKeys += $categoryData.jiraTicket
            }
            
            # Validate required fields
            if (-not $categoryData.jiraTicket) {
                $validationErrors += "❌ Category '$($category.Name)' missing jiraTicket field"
            }
            if (-not $categoryData.tempoAccount) {
                $validationErrors += "❌ Category '$($category.Name)' missing tempoAccount field"
            }
            if (-not $categoryData.aliases -or $categoryData.aliases.Count -eq 0) {
                $validationErrors += "❌ Category '$($category.Name)' missing or empty aliases array"
            }
        }
        
        Write-Host "  ✓ Found $categoryCount work categories" -ForegroundColor Green
        Write-Host "  ✓ Total aliases defined: $totalAliases" -ForegroundColor Green
        
        # Check for example tickets that should be customized
        $exampleTickets = @("TEAM-1234", "PROJ-5678", "ADMIN-90", "ADMIN-91", "ADMIN-92", "SCRUM-100", "PROJ-2000")
        foreach ($ticket in $exampleTickets) {
            if ($issueKeys -contains $ticket) {
                $warnings += "⚠️  Example ticket '$ticket' found - consider customizing with your actual tickets"
            }
        }
    }
    
    # Check for setup instructions still present
    if ($mappingConfig._instructions -or $mappingConfig._example_usage) {
        $warnings += "⚠️  Documentation sections (_instructions, _example_usage) still present - you can remove these when fully configured"
    }
}

# Validate standard day configuration
if ($standardDayConfig -and $mappingConfig) {
    Write-Host "`n4. Validating standard day configuration..." -ForegroundColor Yellow
    
    $daysOfWeek = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
    
    # Build list of all valid aliases
    $validAliases = @()
    foreach ($category in $mappingConfig.workCategories.PSObject.Properties) {
        if ($category.Value.aliases) {
            $validAliases += $category.Value.aliases
        }
    }
    
    foreach ($day in $daysOfWeek) {
        if ($standardDayConfig.standardDays.$day) {
            $dayEntries = $standardDayConfig.standardDays.$day
            Write-Host "  ✓ $day configured with $($dayEntries.Count) entries" -ForegroundColor Green
            
            # Check if tickets in standard day are valid aliases
            foreach ($entry in $dayEntries) {
                if ($entry.ticket -notin $validAliases) {
                    $warnings += "⚠️  Ticket '$($entry.ticket)' used in $day standard day but not found in any work category aliases"
                }
            }
        } else {
            $warnings += "⚠️  No standard day configuration for $day"
        }
    }
}

# Check environment variables
Write-Host "`n5. Checking environment variables..." -ForegroundColor Yellow

$requiredVars = @{
    'TEMPO_API_TOKEN' = $env:TEMPO_API_TOKEN
    'TEMPO_BASE_URL' = $env:TEMPO_BASE_URL
    'TEMPO_ACCOUNT_ID' = $env:TEMPO_ACCOUNT_ID
    'ATLASSIAN_EMAIL' = $env:ATLASSIAN_EMAIL
    'ATLASSIAN_API_TOKEN' = $env:ATLASSIAN_API_TOKEN
}

foreach ($var in $requiredVars.GetEnumerator()) {
    if ([string]::IsNullOrEmpty($var.Value)) {
        $validationErrors += "❌ Environment variable $($var.Key) is not set"
    } else {
        $maskedValue = if ($var.Key -like "*TOKEN*") { "[HIDDEN]" } else { $var.Value }
        Write-Host "  ✓ $($var.Key) = $maskedValue" -ForegroundColor Green
    }
}

# Test API connectivity
$allEnvVarsSet = $requiredVars.Values | ForEach-Object { -not [string]::IsNullOrEmpty($_) } | Where-Object { $_ -eq $false }

if (-not $allEnvVarsSet) {
    Write-Host "`n6. Testing API connectivity..." -ForegroundColor Yellow
    
    # Test Jira auth
    $jiraAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${env:ATLASSIAN_EMAIL}:${env:ATLASSIAN_API_TOKEN}"))
    $jiraHeaders = @{ 'Authorization' = "Basic $jiraAuth"; 'Accept' = 'application/json' }
    
    try {
        $jiraUser = Invoke-RestMethod -Uri "https://relias.atlassian.net/rest/api/2/myself" -Headers $jiraHeaders -TimeoutSec 10
        Write-Host "  ✓ Jira auth OK (user: $($jiraUser.displayName))" -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            $validationErrors += "❌ Jira authentication failed (401). ATLASSIAN_API_TOKEN may be expired or invalid."
        } else {
            $validationErrors += "❌ Jira API unreachable (HTTP $statusCode): $($_.Exception.Message)"
        }
    }
    
    # Test Tempo auth
    $tempoHeaders = @{ 'Authorization' = "Bearer $env:TEMPO_API_TOKEN" }
    $today = Get-Date -Format "yyyy-MM-dd"
    
    try {
        $tempoResp = Invoke-RestMethod -Uri "$env:TEMPO_BASE_URL/worklogs?from=$today&to=$today&limit=1" -Headers $tempoHeaders -TimeoutSec 10
        Write-Host "  ✓ Tempo auth OK" -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            $validationErrors += "❌ Tempo authentication failed (401). TEMPO_API_TOKEN may be expired or invalid."
        } else {
            $validationErrors += "❌ Tempo API unreachable (HTTP $statusCode): $($_.Exception.Message)"
        }
    }
    
    # Test TEMPO_ACCOUNT_ID matches authenticated user
    if ($jiraUser) {
        $jiraAccountId = $jiraUser.accountId
        if ($env:TEMPO_ACCOUNT_ID -ne $jiraAccountId) {
            $warnings += "⚠️  TEMPO_ACCOUNT_ID ($env:TEMPO_ACCOUNT_ID) does not match Jira accountId ($jiraAccountId). This will cause 403 errors if you don't have 'Log work for others' permission."
        } else {
            Write-Host "  ✓ TEMPO_ACCOUNT_ID matches Jira user" -ForegroundColor Green
        }
    }
} else {
    Write-Host "`n6. Skipping API connectivity test (missing env vars)" -ForegroundColor Yellow
}

# Display results
Write-Host "`n=== Validation Results ===" -ForegroundColor Cyan

if ($validationErrors.Count -eq 0) {
    Write-Host "`n✅ Configuration validation passed!" -ForegroundColor Green
    Write-Host "Your Tempo Time Tracker is ready to use." -ForegroundColor Green
} else {
    Write-Host "`n❌ Configuration validation failed!" -ForegroundColor Red
    Write-Host "Please fix the following errors:`n" -ForegroundColor Red
    foreach ($validationError in $validationErrors) {
        Write-Host $validationError -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host $warning -ForegroundColor Yellow
    }
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
if ($validationErrors.Count -gt 0) {
    Write-Host "1. Fix the validation errors above" -ForegroundColor White
    Write-Host "2. Re-run this validation script" -ForegroundColor White
    Write-Host "3. Test with: ./Log-TempoTime.ps1 -Ticket 'standup' -Duration '15m' -WhatIf" -ForegroundColor White
} else {
    Write-Host "1. Test individual entry: ./Log-TempoTime.ps1 -Ticket 'standup' -Duration '15m' -WhatIf" -ForegroundColor White
    Write-Host "2. Test standard day: ./Log-StandardDay.ps1 -WhatIf" -ForegroundColor White
    Write-Host "3. Start logging time!" -ForegroundColor White
}

Write-Host ""