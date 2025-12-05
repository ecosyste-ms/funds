# Audit Log

The `project_allocation_events` table tracks all significant actions, state changes, and API responses for project allocations.

## Schema

- `project_allocation_id` (required)
- `fund_id` (required)
- `allocation_id` (required)
- `invitation_id` (optional)
- `event_type` (required)
- `status` (success, error, pending)
- `message` (text)
- `metadata` (JSON - stores API responses, timing, error details)

## Event Types

**Allocation events:** `payout_started`, `payout_osc_collective`, `payout_non_osc_collective`, `payout_proxy_collective`, `payout_expense_invite`, `payout_completed`, `payout_failed`, `payout_skipped`, `funding_rejected`, `funding_accepted`

**Invitation events:** `invitation_created`, `invitation_email_sent`, `invitation_accepted`, `invitation_rejected`, `expense_created`, `expense_email_sent`, `expense_approved`, `expense_unapproved`, `expense_deleted`, `expense_synced`, `expense_sync_failed`

## Admin View

`/admin/events` - Timeline of all events with filters for fund, event type, and status.

## Usage

Log events from ProjectAllocation:
```ruby
log_event('payout_started', status: 'success', message: 'Starting payout', metadata: { amount: 5000 })
```

Log events from Invitation:
```ruby
log_event('expense_synced', metadata: { old_status: 'DRAFT', new_status: 'APPROVED' })
```

Events are permanent and will not be deleted.
