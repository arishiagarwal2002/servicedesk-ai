# Service Desk AI Assistant — one-page specification

Status: in progress, started 1 October 2026. Nothing here has been validated on
real tickets. All data in the repository is fictional and marked as such.

## What it does

Takes an IT support ticket as it arrived, suggests a category and owning team,
retrieves supporting material from runbooks and past resolved cases, and drafts
a first response for an engineer to accept, edit or reject.

## What it does not do

Version 1 does not send replies, close tickets, change queues in a live system,
reset passwords, run commands, or take any action outside its own database. It
records a proposed action for a person to use. Any of these could be added
later, each as a separate change with its own evaluation.

## Scope boundaries for version 1

- One workflow, English tickets, four categories.
- One fictional tenant.
- Attachment parsing, multilingual tickets, fine-tuning, live service-desk
  connectors and autonomous agents are all out of scope and stay out.

## The four categories

| Category | Provisional team |
| --- | --- |
| Account access | Identity Support |
| Email | Messaging Support |
| VPN / connectivity | Network Support |
| Software installation | Endpoint Support |

Anything that matches none of these, or several at once, goes to a human rather
than being forced into the nearest fit.

## Definition of a working prototype

All five must hold before the prototype is called complete:

1. A new synthetic ticket completes the full journey: intake, triage,
   retrieval, draft, review, stored decision.
2. Every cited source can be opened from the review screen, and the access
   check runs again when it is opened.
3. Unanswerable tickets take the `no_answer` path instead of producing a
   plausible invention.
4. Reviewer edits are stored without overwriting the original suggestion.
5. A reproducible evaluation report states the data, the versions, the sample
   counts and the limitations.

## Success questions this project answers

- How often does the suggested team match the team that should have had the
  ticket first?
- What share of tickets get a definite suggestion at all, and are those
  suggestions better than the ones made under a confidence threshold?
- When the corpus has no answer, does the system say so?
- Do engineers accept the drafts, edit them, or throw them away?

## What would make it a failure

A system that scores well by abstaining on almost everything. A system whose
accuracy figure comes from a test set small enough to be noise. A draft that
reads confidently while citing a source that does not support it. Each of these
is specifically measured so it cannot pass unnoticed.

## Open questions for Keptra

1. Which team would own a pilot, and are these four categories the right ones?
2. Who approves example resolutions, labels and the priority policy?
3. What counts as a useful result, and who decides whether this continues?
4. Can an anonymised historical export be approved, and on what timescale?
