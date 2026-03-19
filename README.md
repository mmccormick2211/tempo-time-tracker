# Tempo Time Tracker

Tempo Time Tracker is a PowerShell-based AI skill for logging and reviewing Jira time entries through the Tempo Timesheets API.

## What This Skill Does

- Logs individual work entries with shorthand ticket aliases
- Logs recurring "standard day" templates from configuration
- Queries and summarizes timesheet data by ticket, day, or account
- Validates local configuration and API connectivity before use

## Repository Layout

```text
tempo-time-tracker/
|-- README.md
|-- SETUP.md
|-- SKILL.md
`-- scripts/
	|-- Get-TempoTimesheet.ps1
	|-- Log-StandardDay.ps1
	|-- Log-TempoTime.ps1
	|-- Validate-Configuration.ps1
	|-- standard-day-config.json
	`-- ticket-mappings.json
```

## Prerequisites

- PowerShell 7.0+
- Tempo API token
- Jira API token and Atlassian email
- Access to the target Jira projects and Tempo accounts

## Environment Variables

Set these variables before running scripts:

```powershell
$env:TEMPO_API_TOKEN = "<tempo-token>"
$env:TEMPO_BASE_URL = "https://api.tempo.io/4"
$env:TEMPO_ACCOUNT_ID = "<atlassian-account-id>"
$env:ATLASSIAN_EMAIL = "<you@company.com>"
$env:ATLASSIAN_API_TOKEN = "<jira-api-token>"
```

## Configuration Files

- `scripts/ticket-mappings.json`: defines work categories, aliases, Jira ticket keys, Tempo account codes, and optional defaults.
- `scripts/standard-day-config.json`: defines recurring weekday templates used by `Log-StandardDay.ps1`.

Run configuration validation before first use:

```powershell
./scripts/Validate-Configuration.ps1
```

## Core Scripts

### `Log-TempoTime.ps1`

Logs a single entry.

```powershell
./scripts/Log-TempoTime.ps1 -Ticket "infra" -Duration "6h30m" -Description "Platform maintenance"
./scripts/Log-TempoTime.ps1 -Ticket "standup" -WhatIf
./scripts/Log-TempoTime.ps1 -Ticket "1:1" -Date "2026-03-18"
```

### `Log-StandardDay.ps1`

Logs all configured recurring entries for a day.

```powershell
./scripts/Log-StandardDay.ps1 -WhatIf
./scripts/Log-StandardDay.ps1
./scripts/Log-StandardDay.ps1 -Date "2026-03-18"
./scripts/Log-StandardDay.ps1 -DayOfWeek "Tuesday" -Date "2026-03-20"
```

### `Get-TempoTimesheet.ps1`

Retrieves and analyzes existing worklogs.

```powershell
./scripts/Get-TempoTimesheet.ps1 -Period Today
./scripts/Get-TempoTimesheet.ps1 -Period ThisWeek -ShowRemaining
./scripts/Get-TempoTimesheet.ps1 -From "2026-03-01" -To "2026-03-19" -GroupBy Account
```

## Recommended Workflow

1. Validate configuration and credentials.
2. Query existing worklogs before adding or correcting entries.
3. Use `-WhatIf` for dry runs.
4. Log entries (single or standard-day).
5. Re-query to confirm totals and avoid duplicates.

## Additional Documentation

- See `SETUP.md` for detailed onboarding instructions.
- See `SKILL.md` for AI-skill usage rules, correction workflows, and conversation patterns.

## Notes

- Tempo writes are non-idempotent. Replaying the same payload can create duplicates.
- Use signature checks and post-write verification when doing corrections or bulk logging.