---
source_id: RB-VPN-01
version: 1
kind: runbook
title: Single-user VPN authentication failure after a password change
available_at: 2026-09-20T00:00:00Z
superseded_at: null
approved: true
tenant_id: demo-tenant
allowed_groups: [service-desk, network-support]
is_synthetic: true
---

# Single-user VPN authentication failure after a password change

Applies when one user cannot authenticate to the VPN shortly after changing or
resetting their password, and ordinary web sign-in still works.

## First checks

1. Confirm the exact error text shown by the VPN client. "Authentication
   failed" and "Connection timed out" have different causes and should not be
   treated as the same symptom.
2. Confirm whether browser-based sign-in to internal web applications succeeds.
   If web sign-in also fails, this is an identity problem rather than a VPN
   problem — use RB-IDENT-02 instead.
3. Check the published service status page for a wider incident. If one is
   open, attach the ticket to it and stop here.

## If there is no wider incident

4. Collect the VPN client version and the operating system build.
5. Collect the approximate time the password was changed and the time the
   first failed connection was attempted.
6. Pass the case to Network Support with the above collected.

## Never do

- Never ask the user for their password, a recovery code or an MFA code. No
  procedure in this runbook requires them, and a request for one should be
  treated as a security incident.
- Never advise the user to disable MFA or to reinstall the VPN client before
  Network Support has reviewed the case.

## Notes

Cached credentials on the endpoint are a common cause and usually resolve on a
restart after a successful web sign-in, but confirm the restart has happened
rather than assuming it.
