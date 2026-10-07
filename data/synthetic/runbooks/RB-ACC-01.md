---
source_id: RB-ACC-01
version: 1
kind: runbook
title: Account lockout after repeated failed sign-in attempts
available_at: 2026-09-18T00:00:00Z
superseded_at: null
approved: true
tenant_id: demo-tenant
allowed_groups: [service-desk, identity-support]
is_synthetic: true
---

# Account lockout after repeated failed sign-in attempts

Applies when a user reports being locked out and the directory shows the
account in a locked state following consecutive failed attempts.

## First checks

1. Confirm the account name and that the lockout is current rather than one
   that has already expired. Lockouts release automatically after the
   configured interval.
2. Check whether the failed attempts came from the user's own device or from
   another source. Repeated failures from an unexpected location are a
   security matter and go to Identity Support immediately, not through the
   ordinary unlock path.
3. Check for a stale credential on a secondary device — a phone mail client or
   a mapped drive holding an old password will re-lock the account within
   minutes of each unlock. Lockouts that recur after a successful unlock are
   almost always this.

## Routing

4. Straightforward lockouts with no suspicious sign-in activity: Identity
   Support, standard priority.
5. Any lockout with failed attempts from an unrecognised source: Identity
   Support, flagged, same day.

## Never do

- Never confirm or deny over a ticket whether a specific password was correct.
- Never ask the user to send their password or a recovery code in a ticket.
- Never unlock an account on the basis of a request alone; follow the verified
  identity check first.
