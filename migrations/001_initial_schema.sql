-- Service Desk AI Assistant — initial schema
--
-- The single most important property of this schema is the separation between
-- what was known when a ticket ARRIVED and what was learned AFTERWARDS.
-- Those live in different tables so that no query can accidentally feed a
-- resolution back into the prediction for its own ticket. Every evaluation
-- number the project reports depends on this holding.
--
--   tickets          what the assistant is allowed to see
--   ticket_outcomes  what happened later  (training signal / history only)
--   gold_labels      the evaluation answers  (never an input)

CREATE EXTENSION IF NOT EXISTS vector;

-- ---------------------------------------------------------------------------
-- 1. Tickets: creation-time facts ONLY.
-- ---------------------------------------------------------------------------
CREATE TABLE tickets (
    ticket_id               TEXT PRIMARY KEY,
    subject                 TEXT        NOT NULL,
    description_at_creation TEXT        NOT NULL,
    service                 TEXT,
    -- Structured facts supplied by the reporter at submission, e.g.
    -- {"users_affected": 1, "site": "london", "business_hours": true}.
    -- Used for the priority matrix. Never inferred by a model.
    impact_facts            JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at              TIMESTAMPTZ NOT NULL,
    -- Every record is explicitly marked. Synthetic and company data must never
    -- be silently mixed in an evaluation run.
    is_synthetic            BOOLEAN     NOT NULL,
    source_batch            TEXT        NOT NULL,
    tenant_id               TEXT        NOT NULL DEFAULT 'demo-tenant'
);

CREATE INDEX tickets_created_at_idx ON tickets (created_at);
CREATE INDEX tickets_synthetic_idx  ON tickets (is_synthetic, source_batch);

-- ---------------------------------------------------------------------------
-- 2. Outcomes: everything learned after the ticket arrived.
--    Separate table, deliberately. Joining this into a prediction is the bug
--    this schema exists to prevent.
-- ---------------------------------------------------------------------------
CREATE TABLE ticket_outcomes (
    ticket_id          TEXT PRIMARY KEY REFERENCES tickets (ticket_id) ON DELETE CASCADE,
    initial_queue      TEXT,
    final_queue        TEXT,
    reassignment_count INTEGER     NOT NULL DEFAULT 0,
    first_response_at  TIMESTAMPTZ,
    resolved_at        TIMESTAMPTZ,
    resolution_text    TEXT
);

-- ---------------------------------------------------------------------------
-- 3. Gold labels: the evaluation answers, reviewed by a human.
--    `valid_initial_team` is NOT the same as `final_queue` — the team that
--    eventually resolved a ticket is not always the team that should have had
--    it first. An engineer labels the intended first queue.
-- ---------------------------------------------------------------------------
CREATE TABLE gold_labels (
    ticket_id          TEXT PRIMARY KEY REFERENCES tickets (ticket_id) ON DELETE CASCADE,
    gold_category      TEXT        NOT NULL,
    valid_initial_team TEXT        NOT NULL,
    -- FALSE where the corpus genuinely cannot answer the ticket. Used to score
    -- correct refusal; without these the abstention metrics are meaningless.
    answerable         BOOLEAN     NOT NULL,
    relevant_source_ids TEXT[]     NOT NULL DEFAULT '{}',
    reviewer           TEXT        NOT NULL,
    labelled_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 4. Evaluation splits, frozen once and never re-rolled.
--    `family_id` groups paraphrases, repeat incidents and related scenarios so
--    near-duplicates cannot land on opposite sides of the split.
-- ---------------------------------------------------------------------------
CREATE TABLE eval_splits (
    ticket_id TEXT PRIMARY KEY REFERENCES tickets (ticket_id) ON DELETE CASCADE,
    split     TEXT NOT NULL CHECK (split IN ('dev', 'val', 'test')),
    family_id TEXT NOT NULL
);

CREATE INDEX eval_splits_family_idx ON eval_splits (family_id);

-- ---------------------------------------------------------------------------
-- 5. Knowledge sources: runbooks and historical resolved cases.
--    available_at / superseded_at are what make honest historical replay
--    possible: retrieval for a ticket created at T may only see sources that
--    existed at T.
-- ---------------------------------------------------------------------------
CREATE TABLE knowledge_sources (
    source_id      TEXT        NOT NULL,
    version        INTEGER     NOT NULL,
    kind           TEXT        NOT NULL CHECK (kind IN ('runbook', 'resolved_case')),
    title          TEXT        NOT NULL,
    body           TEXT        NOT NULL,
    available_at   TIMESTAMPTZ NOT NULL,
    superseded_at  TIMESTAMPTZ,
    approved       BOOLEAN     NOT NULL DEFAULT FALSE,
    tenant_id      TEXT        NOT NULL DEFAULT 'demo-tenant',
    allowed_groups TEXT[]      NOT NULL DEFAULT '{}',
    is_synthetic   BOOLEAN     NOT NULL,
    PRIMARY KEY (source_id, version)
);

CREATE INDEX knowledge_sources_window_idx ON knowledge_sources (available_at, superseded_at);

-- ---------------------------------------------------------------------------
-- 6. Chunks and embeddings.
--    Access metadata is denormalised onto the chunk so the eligibility filter
--    runs in the same query as the vector search, not as a post-filter.
-- ---------------------------------------------------------------------------
CREATE TABLE source_chunks (
    chunk_id        BIGSERIAL PRIMARY KEY,
    source_id       TEXT        NOT NULL,
    version         INTEGER     NOT NULL,
    chunk_index     INTEGER     NOT NULL,
    text            TEXT        NOT NULL,
    embedding       VECTOR(1536),          -- matches text-embedding-3-small
    embedding_model TEXT        NOT NULL,
    corpus_version  TEXT        NOT NULL,
    available_at    TIMESTAMPTZ NOT NULL,
    superseded_at   TIMESTAMPTZ,
    tenant_id       TEXT        NOT NULL,
    allowed_groups  TEXT[]      NOT NULL DEFAULT '{}',
    FOREIGN KEY (source_id, version) REFERENCES knowledge_sources (source_id, version) ON DELETE CASCADE,
    UNIQUE (source_id, version, chunk_index, corpus_version)
);

CREATE INDEX source_chunks_vec_idx
    ON source_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX source_chunks_filter_idx
    ON source_chunks (tenant_id, corpus_version, available_at);

-- ---------------------------------------------------------------------------
-- 7. Analyses: one run of the system over one ticket.
--    Every version stamp needed to reproduce the result is stored with it.
-- ---------------------------------------------------------------------------
CREATE TABLE analyses (
    analysis_id        TEXT PRIMARY KEY,
    ticket_id          TEXT        NOT NULL REFERENCES tickets (ticket_id) ON DELETE CASCADE,
    suggestion_version INTEGER     NOT NULL,
    status             TEXT        NOT NULL
        CHECK (status IN ('ready_for_review', 'needs_information', 'no_answer', 'failed')),
    suggested_category TEXT,
    suggested_team     TEXT,
    confidence         REAL,
    priority           TEXT,
    draft              TEXT,
    -- [{"claim": ..., "source_id": ..., "version": ..., "passage": ...}, ...]
    citations          JSONB       NOT NULL DEFAULT '[]'::JSONB,
    questions          JSONB       NOT NULL DEFAULT '[]'::JSONB,
    reason             TEXT,
    classifier_version TEXT,
    model_version      TEXT,
    prompt_version     TEXT,
    corpus_version     TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (ticket_id, suggestion_version)
);

-- ---------------------------------------------------------------------------
-- 8. Review events. The original suggestion is never overwritten by an edit.
--    `suggestion_version` is checked on write: a review of a stale version is
--    rejected with 409 rather than silently applied to a newer draft.
--    `idempotency_key` stops a double-click creating two review events.
-- ---------------------------------------------------------------------------
CREATE TABLE review_events (
    review_id          TEXT PRIMARY KEY,
    analysis_id        TEXT        NOT NULL REFERENCES analyses (analysis_id) ON DELETE CASCADE,
    suggestion_version INTEGER     NOT NULL,
    reviewer_id        TEXT        NOT NULL,
    action             TEXT        NOT NULL CHECK (action IN ('accepted', 'edited', 'rejected')),
    edited_text        TEXT,
    corrected_category TEXT,
    corrected_team     TEXT,
    reason             TEXT,
    idempotency_key    TEXT        NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (analysis_id, idempotency_key)
);

CREATE INDEX review_events_analysis_idx ON review_events (analysis_id, created_at);
