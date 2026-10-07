# Service Desk AI Assistant

A ticket-triage and response-drafting assistant with a human review step.
Classifies an incoming IT support ticket, retrieves cited evidence from
runbooks and past resolutions, drafts a first response, and records an
engineer's decision on it. Nothing is sent or changed automatically.

**Status: in progress.** Built and evaluated on fictional data. No real
company tickets are in this repository and no results on real tickets are
claimed. See `docs/spec.md` for scope and the definition of done.

## Why it is built this way

Three design decisions carry most of the weight:

1. **Creation-time facts are separated from outcomes at the schema level.**
   `tickets` holds only what was known when the ticket arrived; resolutions and
   final queues live in `ticket_outcomes`; evaluation answers live in
   `gold_labels`. No query can accidentally feed a ticket's own resolution into
   its own prediction. Every accuracy number depends on this.

2. **Sources carry an availability window.** Retrieval for a ticket created at
   time T sees only sources that existed at T. A runbook edited last week
   cannot be used to answer a ticket from last month.

3. **The system abstains.** Low-confidence classifications and unsupported
   drafts take the `needs_information` or `no_answer` path. Coverage is
   reported next to accuracy, because a system that refuses everything scores
   well on the few answers it gives.

## Running it locally

```bash
docker compose up -d db                       # Postgres with pgvector
psql "$DATABASE_URL" -f migrations/001_initial_schema.sql
cp .env.example .env                          # MODEL_PROVIDER=mock to start
```

The mock provider lets the API, review screen and database be built and tested
before any model endpoint is connected. Its output is not evidence of anything;
it exists so the interface work does not block on access.

## Layout

```
app/api/           request validation, auth context, routes
app/triage/        classifier training, prediction, category -> team mapping
app/retrieval/     permission and time filters, ranking, evidence selection
app/generation/    provider adapter, prompts, output schema, validation
app/reviews/       version checks, review events, audit
app/db/            queries and connection handling
migrations/        schema
data/synthetic/    fictional tickets, runbooks, taxonomy
data/eval/         split manifest, gold labels, scoring
ui/                review screen
tests/             behavioural checks, especially the failure paths
docs/              spec, architecture, evaluation reports
```

## Next steps

1. Extend `data/synthetic/tickets.jsonl` from 5 seed tickets to ~60, and the
   runbooks from 2 to 8. Write them by hand first — the point is to understand
   what correct behaviour looks like before automating anything.
2. Freeze the split manifest (dev / val / test) with `family_id` grouping so
   near-duplicates cannot straddle the split.
3. Build the API and review screen against the mock provider.
4. Fit the TF-IDF + logistic regression baseline and record its confusion
   matrix.

## A note on the data

Every ticket, runbook, service name and team name in this repository is
invented. `is_synthetic` is stored on every record and is not optional. Keptra
procedures are not represented here, and the provisional queue names are
placeholders until an engineer confirms the real ones.
