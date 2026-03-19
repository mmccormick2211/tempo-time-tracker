---
name: tempo-time-tracker
description: V1.0 - Log time to Jira tickets via Tempo Timesheets API. Use for standard day logging, week corrections, overlap cleanup, and bounded backfills such as "up to the current time". Configuration-driven with work categories and customizable daily schedules.
compatibility: Requires Tempo API token, Jira API token, and PowerShell 7.0+ for automation
---

# Tempo Time Tracker

Automate time logging to Jira tickets using the Tempo Timesheets API with PowerShell scripts. This skill uses configuration files for ticket mappings and daily templates, making it customizable for any team's workflow.

## Project Structure

```
tempo-time-tracker/
├── SKILL.md                                    # Copilot agent instructions
├── SETUP.md                                    # Quick setup guide for users
├── .gitignore                                 # Git ignore file
└── scripts/
    ├── Get-TempoTimesheet.ps1                 # Query and analyze timesheet data
    ├── Log-StandardDay.ps1                    # Bulk logging with day templates
    ├── Log-TempoTime.ps1                      # Individual time entry logging
    ├── Validate-Configuration.ps1             # Configuration validation tool
    ├── standard-day-config.json               # Your daily schedule templates (customize this)
    └── ticket-mappings.json                   # Your ticket mappings (customize this)
```

## Prerequisites

Before using this tool, ensure you have:

1. **PowerShell** (7.0+ recommended)
2. **Tempo API access** via your organization's Jira instance
3. **Jira API access** for issue lookups

### Setup Instructions

1. **Get Tempo API Token**:
   - Log into Tempo at your organization's Jira instance
   - Navigate to Settings → API Integration
   - Generate a new API token
   - Store token securely

2. **Get Jira API Token**:
   - Log into your Jira instance
   - Go to Account Settings → Security → API Tokens
   - Create API token
   - Note your email address for API authentication

3. **Set Environment Variables**:
   ```bash
   export TEMPO_API_TOKEN="your-tempo-token-here"
   export TEMPO_BASE_URL="https://api.tempo.io/4"
   export TEMPO_ACCOUNT_ID="your-account-id-here"  # Your Atlassian account ID (find in worklogs API response as "authorAccountId")
   export ATLASSIAN_EMAIL="your.email@company.com"
   export ATLASSIAN_API_TOKEN="your-jira-api-token-here"
   ```

4. **Test Connection**:
   ```bash
   curl -H "Authorization: Bearer $TEMPO_API_TOKEN" \
        "$TEMPO_BASE_URL/worklogs?limit=1"
   # Look for "authorAccountId" in the response - that's your TEMPO_ACCOUNT_ID
   ```

5. **Configure Your Tickets**:
   - Update [standard-day-config.json](scripts/standard-day-config.json) with your team's tickets and schedule
   - Edit the ticket mappings in the PowerShell scripts for your organization's ticket structure

## Configuration

The tool uses two configuration files for complete customization:

### 1. Work Categories (`scripts/ticket-mappings.json`)

This file defines your work categories, each containing all related information in one place:
- **aliases**: Multiple friendly names for the same work (e.g., "1:1", "one-on-one", "121")
- **jiraTicket**: The Jira ticket key
- **tempoAccount**: The Tempo account code
- **defaults** (optional): defaultDuration, defaultDescription, defaultStartTime for recurring activities

**Structure example:**
```json
"meetings-1on1": {
  "aliases": ["1:1", "1on1", "one-on-one", "121"],
  "jiraTicket": "INT-5",
  "tempoAccount": "INT",
  "defaultDuration": "1h",
  "defaultDescription": "1:1 meeting",
  "defaultStartTime": "14:00:00"
}
```

**Important - Account Codes**:
- **OpEx accounts** (operational/maintenance work):
  - `GEN-MAINT` - General-Maintenance (infrastructure/ops work on non-INT tickets)
  - `INT` - Internal (ONLY for INT-* prefixed tickets: meetings, PTO, professional development)
  - Use generic categories and aliases for these routine operational activities

- **CapEx accounts** (capital/development work - finance tracked):
  - `GEN-DEV` - General-Dev and Design
  - `GEN-PROJ` - General-Project Management
  - `GEN-RES` - General-Research
  - `GEN-TEST` - General-Testing
  - ALWAYS log explicitly to specific Jira tickets with exact descriptions
  - Used for finance tracking and must be intentional and accurate
  - Do NOT include CapEx work in generic standard day templates or use generic aliases

- **Product-specific accounts** also available (consult your org's Tempo instance):
  - Academy: ACA-DEV, ACA-MAINT, ACA-PROJ, ACA-RES, ACA-TEST
  - Compliance: COMP-DEV, COMP-MAINT, COMP-PROJ, COMP-RES, COMP-TEST
  - FeedTrail: FEED-DEV, FEED-MAINT, FEED-PROJ, FEED-RES, FEED-TEST
  - FreeCME: FREE-DEV, FREE-MAINT, FREE-PROJ, FREE-RES, FREE-TEST
  - Media: MEDIA-DEV, MEDIA-MAINT, MEDIA-PROJ, MEDIA-RES, MEDIA-TEST
  - Nurse Recruiting: NURSE-DEV, NURSE-MAINT, NURSE-PROJ, NURSE-RES, NURSE-TEST
  - Pflegeclever: PFLE-DEV, PFLE-MAINT, PFLE-PROJ, PFLE-TEST
  - Population Health: POP-DEV, POP-PROJ, POP-RES, POP-TEST
  - Woundcare: WOUND-DEV, WOUND-MAINT, WOUND-PROJ, WOUND-RES, WOUND-TEST

**Critical Restriction**: The `INT` account code can ONLY be used with INT-prefixed Jira tickets (e.g., INT-14, INT-5). For non-INT tickets, you must use GEN-* or product-specific account codes.

**To customize:**
1. Open `scripts/ticket-mappings.json` in your editor
2. For each work category:
   - Update `jiraTicket` with your actual Jira ticket key
   - Update `tempoAccount` with your Tempo account code
   - Modify `aliases` to match your team's vocabulary
   - Set defaults for recurring activities (optional)
3. Add new categories or remove unused ones as needed
4. Remove documentation sections (`_instructions`, `_example_usage`) when complete

### 2. Standard Day Templates (`scripts/standard-day-config.json`)

Defines your weekly schedule using the shorthand ticket names from your mappings.

**To customize:**
1. Open `scripts/standard-day-config.json` in your editor
2. For each day of the week, update the entries:
   - Replace shorthand `ticket` values with ones from your ticket mappings
   - Adjust `duration` to match your actual meeting/work times
   - Update `description` to be meaningful for your team
   - Set `startTime` to match your schedule
3. Ensure each day's entries total your standard work hours (usually 8h)
4. Remove the `_comments` section if desired

## Standard Day Templates

Your standard work week is configured in `scripts/standard-day-config.json`. Each day template defines recurring items (standups, 1:1s, training sessions, etc.).

**Example Configuration**:
- **Monday-Thursday**: Daily standups + project work
- **Tuesday**: Also includes 1:1 meetings
- **Friday**: Lighter meeting schedule

Customize the configuration file to match your team's schedule including meeting times, durations, and ticket mappings.

View and edit your configuration in [standard-day-config.json](scripts/standard-day-config.json).

### Quick Standard Day Logging

**Trigger Phrases** (use fuzzy matching):
- "log my standard day" / "log standard day"
- "log my usual day" / "log usual day"
- "log my typical day" / "log typical day"
- "log today" (when clearly referring to full day)
- "log the day" / "log my day"
- "log my standard week" / "log standard week" / "log the week"
- "log my usual week"

**Important**: Standard day templates contain RECURRING ITEMS ONLY (standups, 1:1s, etc.) - the agent will prompt users to log additional work separately after logging the standard day.

**Workflow when user requests standard day logging**:

1. **Determine the date**: Default to today unless user specifies otherwise ("yesterday", "last friday", specific date)

2. **Check existing entries**: Before logging, check if time has already been logged for that date:
   ```powershell
   ./scripts/Get-TempoTimesheet.ps1 -From "YYYY-MM-DD" -To "YYYY-MM-DD"
   ```
   - If entries exist, ask: "You already have X hours logged for [date]. Do you want to add more, replace, or skip?"
   - Show existing entries so user can see what's already there

3. **Preview what will be logged**: Show the user what entries will be logged based on the day of week from `standard-day-config.json`:
   - "I'll log for [DayOfWeek], [Date]:"
   - List all entries with durations and tickets
   - Show total hours from standard day

4. **Confirm before logging**: Unless user explicitly says "just log it" or similar, confirm before submitting

5. **Execute**: Run `./scripts/Log-StandardDay.ps1` with appropriate date

6. **Check remaining time**: After logging standard day, calculate remaining hours:
   - If logged hours < 8h (or user's standard work day), inform the user: "Standard day logged (X hours). You have Y hours remaining to reach 8 hours. Do you have any additional work to log?"
   - Prompt user to log remaining time using individual entries
   - Help user log additional entries using `Log-TempoTime.ps1` for each work item
   - **If user says no or doesn't have more to log**: That's OK - acknowledge and inform them they can add more later if needed

### Log Standard Week Workflow

**When user requests logging standard week** ("log my standard week", "log the week"):

1. **Determine the week**: Default to current work week (Mon-Fri) unless user specifies otherwise
2. **Check each day**: Query existing time for EACH day before logging
3. **Ask about customization**: "Do you want to log just the recurring items from your config, or do you have additional customizations for each day?"
   - **If just recurring items**: Proceed to log all days with standard config entries only, prompt for remaining time after each day
   - **If custom items**: Iterate day by day, asking about additional work for each day
4. **For each day (Mon-Fri)**:
   - Check existing entries for that specific date
   - If time already logged, ask whether to skip, add, or replace
   - Preview standard day entries for that day of week
   - Log if user confirms
   - Calculate remaining hours (target 8h for full day)
   - If custom items mode: Ask "What additional work for [Day]?" and help log each item
   - If recurring items only mode: Prompt "[Day] logged (Xh). You have Yh remaining. Additional work to log?" and wait for response
   - Continue until day reaches 8h or user confirms no more time
5. **Summary**: After completing all days, show weekly total and any days that need more time

## Correction Workflow

Use this workflow when fixing an already-logged day or week instead of creating entries blindly.

1. Query existing worklogs for the target dates first.
2. Build a working table with: worklog ID, date, start time, end time, duration, ticket, account, description.
3. Identify which entries are template-driven, which are manual, and which are explicit user exceptions.
4. Apply priority rules before creating anything new.
5. Delete or replace only the entries that are actually wrong.
6. Re-query and verify totals and overlaps after every correction batch.

### Priority Rules

- Sick time trumps all other worklogs.
- PTO or other full-day time off should replace normal template entries for that date.
- Manual entries provided by the user should be preserved unless the user explicitly asks to remove them.
- Named meetings beat generic catchall work such as monthly ops buckets.
- Future meetings should be preserved unless the user explicitly asks to remove them.

### Duplicate Prevention

Tempo will accept duplicate worklogs with the same date, time, duration, account, and description. It does not protect against accidental replays.

Before creating a worklog, compare against existing entries using this exact signature:

`Date | StartTime | TimeSpentSeconds | AccountCode | Description`

Practical rules:

- If the exact signature already exists, do not create another entry.
- If a retry happens after a partial failure, re-query first and only create missing signatures.
- After any bulk create, run a duplicate check before reporting completion.

### Overlap Prevention

Do not assume a standard template can be reapplied safely.

Before creating a new entry:

1. Compute the candidate start and end time.
2. Compare it against every existing entry on that date.
3. If it overlaps, decide whether the existing entry should stay based on the priority rules.
4. Only create the new entry after the overlap is resolved.

### "Up To Current Time" Requests

Treat requests like "only up to the current time" as bounded backfills, not full-day rewrites.

Workflow:

1. Get the current local time.
2. Query today's existing entries.
3. Preserve later meetings unless the user explicitly says to remove them.
4. Fill only gaps that end at or before the current time, or before the next preserved meeting.
5. Do not backfill time that has not elapsed yet.

### Weekly Correction Pattern

When the user asks to correct a specific week:

1. Query the full week first.
2. Compare actual entries to the standard template.
3. Apply user-specified exceptions for that week only.
4. Remove template items that should not occur that week, such as one-off deployment meetings.
5. Add training or other filler work only into the remaining open time.
6. Verify each corrected day totals the intended amount and has no overlaps.

### Recommended Verification Checks

Use these checks after any correction run:

- Daily totals by date
- Overlap scan by date
- Duplicate signature scan for created entries
- Final listing of worklog IDs for the edited dates

The key lesson is that Tempo write operations should be treated as non-idempotent. Safe workflows are always: read, compare, modify, verify.

**Script Usage**:

```powershell
# Log today's standard day (auto-detects day of week)
./scripts/Log-StandardDay.ps1

# Log a standard day for a specific date
./scripts/Log-StandardDay.ps1 -Date "2026-02-07"

# Preview what would be logged without submitting
./scripts/Log-StandardDay.ps1 -WhatIf

# Override day template for a specific date
./scripts/Log-StandardDay.ps1 -DayOfWeek "Tuesday" -Date "2026-02-10"
```

**Important**: Standard day configurations in `scripts/standard-day-config.json` should contain **RECURRING ITEMS ONLY** (standups, 1:1s, team meetings, training sessions, etc.). Do NOT include infrastructure work or filler entries to reach 8 hours. The agent will prompt users to log additional work separately after logging the standard day.

## Individual Entry Logging

For single time entries (not a full standard day), use `scripts/Log-TempoTime.ps1`:

**Using Work Category Aliases:**

```powershell
# Log a 1:1 meeting (uses ANY alias from the category)
./scripts/Log-TempoTime.ps1 -Ticket "1:1" -Duration "30m"
./scripts/Log-TempoTime.ps1 -Ticket "one-on-one"  # Same result
./scripts/Log-TempoTime.ps1 -Ticket "121"  # Same result

# Log standup (default duration applies automatically)
./scripts/Log-TempoTime.ps1 -Ticket "standup"
./scripts/Log-TempoTime.ps1 -Ticket "daily"  # Same result

# Log infrastructure/opex work with custom description
./scripts/Log-TempoTime.ps1 -Ticket "infra" -Duration "6h30m" -Description "Server maintenance"
./scripts/Log-TempoTime.ps1 -Ticket "opex" -Duration "6h30m" -Description "Server maintenance"  # Same result

# PTO for specific date
./scripts/Log-TempoTime.ps1 -Ticket "pto" -Date "2026-02-14"

# Infrastructure work (shorter form)
./scripts/Log-TempoTime.ps1 -Ticket "infra" -Duration "4h" -Description "Platform updates"
```

**Ad-hoc Entry to Specific Ticket:**

For work not in your categories, use the actual Jira ticket key:

```powershell
# Log directly to a specific Jira ticket (bypasses work categories)
# Note: You'll need to manually specify the account if required
./scripts/Log-TempoTime.ps1 -Ticket "PROJ-9999" -Duration "2h" -Description "Special project work"
```

The script automatically handles:
- ✅ Alias → ticket mapping (any alias from a category works)
- ✅ Ticket → account code mapping (from category definition)
- ✅ Default duration, description, and start time (if defined in category)
- ✅ Duration parsing (6h30m → 23400 seconds)
- ✅ Issue ID lookup from Jira
- ✅ Tempo API submission with attributes

## Example Conversations

### Example 1: Standard Day with Additional Time

**User**: "Log my usual day"

**Assistant**:
1. Checks existing time for today (Feb 10, 2026 - Tuesday)
2. Finds no existing entries
3. Shows preview: "I'll log for Tuesday, February 10, 2026:
   - 15m → Team Standup (INT-14) at 9:00 AM
   - 1h → 1:1 meeting (INT-5) at 2:00 PM
   Total: 1h 15m"
4. User confirms
5. Logs standard day entries
6. Informs: "✓ Standard day logged (1h 15m). You have 6h 45m remaining to reach 8 hours. Do you have any additional work to log?"
7. User responds: "Log 6h 45m to infra"
8. Assistant logs: `./scripts/Log-TempoTime.ps1 -Ticket "infra" -Duration "6h45m"`
9. Confirms: "✓ Logged 6h 45m to SYS-XXXX (GEN-MAINT). Total for today: 8 hours."

---

### Example 2: Partial Day (User Still Working)

**User**: "Log my standard day" (when user has no more time to log)

**Assistant**:
1. Checks existing time for today
2. Finds no existing entries
3. Logs standard day (15m standup)
4. Informs: "✓ Standard day logged (15m). You have 7h 45m remaining to reach 8 hours. Do you have any additional work to log?"
5. User responds: "No, I'm still working"
6. Confirms: "No problem! You can log additional time later as you complete work. Current total: 15m."

---

### Example 3: Standard Week with Customizations

**User**: "Log my standard week"

**Assistant**:
1. Checks existing time for Mon Feb 9 - Fri Feb 13, 2026
2. Finds Monday and Tuesday already have 8h each
3. Shows: "Monday (8h) and Tuesday (8h) already complete. I'll log Wed-Fri."
4. Asks: "Do you want to log just the recurring items from your config, or do you have additional customizations for each day?"
5. User: "I have customizations"
6. For Wednesday:
   - Shows preview: "15m → Team Standup (INT-14)"
   - Logs standard day
   - Asks: "Wednesday logged (15m). You have 7h 45m remaining. What additional work for Wednesday?"
   - User: "Log 7h 45m opex work"
   - Logs infrastructure time
   - Confirms: "✓ Wednesday complete (8h)"
7. For Thursday:
   - Shows preview: "15m → Team Standup (INT-14)"
   - Logs standard day
   - Asks: "Thursday logged (15m). You have 7h 45m remaining. What additional work for Thursday?"
   - User: "Log 5h infra and 2h meetings"
   - Logs both entries
   - Confirms: "✓ Thursday complete (7h 45m). 15m remaining - any more to log?"
   - User: "No"
8. For Friday:
   - Shows preview: "15m → Team Standup (INT-14)"
   - Logs standard day
   - Asks: "Friday logged (15m). You have 7h 45m remaining. What additional work for Friday?"
   - User: "Log 7h 45m infra"
   - Logs infrastructure time
9. Summary: "✓ Week logged. Total: 40 hours. Thursday has 15m remaining (7h 45m logged)."

---

### Example 4: Standard Week (Recurring Items Only)

**User**: "Log my standard week"

**Assistant**:
1. Checks existing time for Mon Feb 9 - Fri Feb 13, 2026
2. All days are empty
3. Asks: "Do you want to log just the recurring items from your config, or do you have additional customizations for each day?"
4. User: "Just recurring items"
5. For Monday:
   - Shows preview: "15m → Team Standup (INT-14)"
   - Logs standard day
   - Informs: "✓ Monday logged (15m). You have 7h 45m remaining. Additional work to log?"
   - User: "Not yet, still working"
6. For Tuesday:
   - Shows preview: "15m → Team Standup (INT-14), 1h → 1:1 meeting (INT-5)"
   - Logs standard day
   - Informs: "✓ Tuesday logged (1h 15m). You have 6h 45m remaining. Additional work to log?"
   - User: "No"
7. Continues for Wed-Fri with same pattern
8. Summary: "✓ Recurring items logged for Mon-Fri. You can add additional work as you complete it throughout the week."

---

### Example 5: Existing Time Check

**User**: "Log my standard day" (when time already exists)

**Assistant**:
1. Checks existing time for today
2. Finds: "You already have 7h 45m logged for February 10, 2026:
   - 7h 45m → SYS-XXXX (Infrastructure work)
   - Total: 7h 45m
   Do you want to add standard day entries (may create duplicates), replace existing, or skip?"
3. Waits for user decision before proceeding

---

### Example 6: Individual Entry

**User**: "Log 6h 30m to infra"

**Assistant**:
1. Maps 'infra' → SYS-XXXX (GEN-MAINT)
2. Runs `./scripts/Log-TempoTime.ps1 -Ticket "infra" -Duration "6h30m"`
3. Confirms: "✓ Logged 6h 30m to SYS-XXXX (GEN-MAINT) on 2026-02-10 (worklog #12345)"

---

### Example 7: Individual Entry with Date

**User**: "Log 1:1 for yesterday"

**Assistant**:
1. Recognizes shorthand: '1:1' → INT-5, defaults to 1h duration
2. Runs `./scripts/Log-TempoTime.ps1 -Ticket "1:1" -Date "2026-02-09"`
3. Confirms: "✓ Logged 1h to INT-5 (INT) - 1:1 meeting on 2026-02-09 (worklog #11111)"

---

### Example 8: Time Off

**User**: "Log 8h pto for yesterday"

**Assistant**:
1. Maps 'pto' → INT-14 (INT)
2. Runs `./scripts/Log-TempoTime.ps1 -Ticket "pto" -Duration "8h" -Date "2026-02-09"`
3. Confirms: "✓ Logged 8h to INT-14 (INT) on 2026-02-09 (worklog #22222)"

## Querying Your Timesheet

Use the `scripts/Get-TempoTimesheet.ps1` script to analyze your logged time.

### Quick Queries

**Today's hours**:
```powershell
./scripts/Get-TempoTimesheet.ps1 -Period Today
```

**This week with remaining hours**:
```powershell
./scripts/Get-TempoTimesheet.ps1 -Period ThisWeek -ShowRemaining
```

**Last week by day**:
```powershell
./scripts/Get-TempoTimesheet.ps1 -Period LastWeek -GroupBy Day
```

**This month by ticket (top 5)**:
```powershell
./scripts/Get-TempoTimesheet.ps1 -Period ThisMonth -GroupBy Ticket -Top 5
```

**Custom date range by account**:
```powershell
./scripts/Get-TempoTimesheet.ps1 -From "2026-01-19" -To "2026-01-24" -GroupBy Account
```

### Available Options

| Parameter | Values | Description |
|-----------|--------|-------------|
| `-Period` | Today, ThisWeek, LastWeek, ThisMonth, LastMonth | Pre-defined time periods |
| `-From` / `-To` | YYYY-MM-DD | Custom date range |
| `-GroupBy` | Ticket, Day, Account | How to group results |
| `-Top` | Number (default: 10) | Show top N tickets |
| `-ShowRemaining` | Switch | Calculate remaining hours based on 40hr week |

### Output Features

- ✅ **Total hours logged** with period summary
- ✅ **Remaining hours** calculation (8hr/day, 40hr/week)
- ✅ **Breakdown by ticket** with percentage distribution
- ✅ **Daily view** with completion status (✓/⚠/✗)
- ✅ **Account analysis** for capitalization tracking
- ✅ **Entry counts** to identify patterns

## Error Handling

Common errors:
- `401 Unauthorized`: Invalid or expired API token
- `404 Not Found`: Issue key doesn't exist or user lacks access
- `400 Bad Request`: Invalid date format or missing required fields
