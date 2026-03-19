# Quick Setup Guide

This guide will help you get the Tempo Time Tracker configured for your team.

## Prerequisites Checklist

- [ ] PowerShell 7.0+ installed
- [ ] Access to your organization's Jira instance
- [ ] Tempo plugin available in your Jira
- [ ] Admin privileges to create API tokens

## Step-by-Step Setup

### 1. API Token Setup

**Tempo API Token:**

1. Log into your Jira instance
2. Navigate to Tempo → Settings → API Integration
3. Generate new API token
4. Copy token (you'll need this for environment variables)

**Jira API Token:**

1. Go to Jira → Profile → Personal Access Tokens
2. Create new token
3. Copy token and note your email address

### 2. Environment Variables

Create these environment variables (add to your `.bashrc`, `.zshrc`, or PowerShell profile):

```bash
# Required for Tempo API
export TEMPO_API_TOKEN="your-tempo-api-token-here"
export TEMPO_BASE_URL="https://api.tempo.io/4"
export TEMPO_ACCOUNT_ID="your-tempo-account-id"

# Required for Jira API (issue lookups)
export ATLASSIAN_EMAIL="your.email@company.com"
export ATLASSIAN_API_TOKEN="your-jira-api-token-here"
```

**Finding your Account ID:**

```bash
# Get your account ID from recent worklogs
curl -H "Authorization: Bearer $TEMPO_API_TOKEN" \
     "https://api.tempo.io/4/worklogs?limit=1"

# Look for the "authorAccountId" field in the response
# Example response:
# {
#   "results": [{
#     "authorAccountId": "5d123abc456def789",  <-- This is your TEMPO_ACCOUNT_ID
#     "issueKey": "INT-14",
#     ...
#   }]
# }
```

Alternatively, go to Tempo in your browser and check your profile/settings for your Account ID.

### 3. Configure Your Tickets

**A. Identify Your Operational Tickets**
List your team's recurring work tickets:

- Daily standup meetings → `SCRUM-100`
- Sprint activities → `SCRUM-101`, `SCRUM-102`
- Development work → `PROJ-2000`
- Administrative tasks → `ADMIN-10`
- Time off/PTO → `HR-51`, `HR-52`

**B. Edit Work Categories Configuration**

Open `scripts/ticket-mappings.json` - each work category is one complete block with all related info:

**Example 1: Daily Standup (with defaults for recurring meeting)**

```json
"standup": {
  "aliases": ["standup", "daily", "scrum"],
  "jiraTicket": "YOUR-STANDUP-TICKET",
  "tempoAccount": "OVERHEAD",
  "defaultDuration": "15m",
  "defaultDescription": "Daily Standup",
  "defaultStartTime": "09:00:00"
}
```

**Example 2: Project Work (ad-hoc, no defaults)**

```json
"project-work": {
  "aliases": ["dev", "development", "coding", "project"],
  "jiraTicket": "YOUR-PROJECT-TICKET",
  "tempoAccount": "BILLABLE"
}
```

**Example 3: Infrastructure Work (multiple aliases, one ticket)**

```json
"infrastructure": {
  "aliases": ["infra", "opex", "infrastructure", "ops", "maintenance"],
  "jiraTicket": "OPS-5678",
  "tempoAccount": "GEN-MAINT"
}
```

**C. Update Standard Day Configuration**

Open `scripts/standard-day-config.json` and customize:

1. Replace example shorthand names (e.g., "standup", "project-work") with your ticket mappings
2. Adjust `startTime` and `duration` for each entry to match your schedule
3. Add or remove entries as needed for your team
4. Verify each day totals 8 hours (or your standard work day)

### 4. Test Your Configuration

**Run the configuration validator:**

```powershell
./scripts/Validate-Configuration.ps1
```

**Test ticket mapping configuration:**

```powershell
# Check if configuration files are valid JSON
pwsh -c "Test-Json (Get-Content scripts/ticket-mappings.json -Raw)"
pwsh -c "Test-Json (Get-Content scripts/standard-day-config.json -Raw)"
```

**Test individual entry (preview mode):**

```powershell
./scripts/Log-TempoTime.ps1 -Ticket "standup" -Duration "15m" -WhatIf
```

**Test standard day (preview mode):**

```powershell
./scripts/Log-StandardDay.ps1 -WhatIf
```

**View current timesheet:**

```powershell
./scripts/Get-TempoTimesheet.ps1 -Period Today
```

### 5. Common Issues

**"Configuration file not found"**

- Ensure `scripts/ticket-mappings.json` exists and is readable
- Check you're running commands from the tempo-time-tracker directory

**"401 Unauthorized"**

- Check API tokens are correct and not expired
- Verify environment variables are set in current session

**"404 Not Found"**

- Check Jira ticket keys in your mappings are correct and accessible
- Verify ticket keys exist in your Jira instance

**"Missing required field"**

- Check if your Tempo instance requires additional work attributes
- Verify account codes in mappings match your Tempo configuration

## Practical Operating Guidance

These workflow rules came out of real correction work against the Tempo API and are worth following every time.

### 1. Always Read Before Write

Before logging a day or week, query the existing worklogs for the exact date range first. Include worklog ID, date, start time, duration, ticket, account, and description. This gives you the information needed to delete or replace specific entries safely.

### 2. Treat Tempo Writes As Non-Idempotent

Posting the same payload twice creates duplicates. Tempo does not automatically collapse or reject repeated worklogs.

Use a signature check before every create:

`Date | StartTime | TimeSpentSeconds | AccountCode | Description`

If a matching signature already exists, skip creation.

### 3. Resolve Overlaps Explicitly

Do not assume standard templates fit cleanly onto edited days.

- Sick time overrides everything else.
- PTO or other full-day time off replaces the normal day template.
- Manual user-entered worklogs stay unless the user asks to remove them.
- Named meetings should generally be kept over generic catchall work.

### 4. Preserve Future Meetings By Default

If a user asks to fill time only up to now, keep later meetings unless they explicitly ask for removal. Only log elapsed open time.

### 5. Re-Query After Every Correction Batch

After deletions or inserts:

1. Recalculate daily totals.
2. Scan for overlaps.
3. Check for duplicate signatures.
4. Confirm the final worklog IDs for the edited dates.

This is faster than trying to reason about the final state from assumptions alone.

## Next Steps

Once setup is complete:

1. Review [SKILL.md](SKILL.md) for detailed usage instructions and examples
2. Customize `scripts/ticket-mappings.json` with your team's tickets
3. Adjust `scripts/standard-day-config.json` to match your daily schedule
4. Test with `-WhatIf` parameter before submitting real entries

## Questions?

Need help? Check the inline comments in the configuration files for guidance.
