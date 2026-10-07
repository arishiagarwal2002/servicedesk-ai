"""API and model-output contracts.

Two kinds of schema live here and they are deliberately separate:

  * API contracts   — what the review UI and any caller exchange with the service.
  * DraftOutput     — what the language model is required to return.

DraftOutput is validated before anything reaches a reviewer. A model that
returns an unparseable body, cites a source that was not retrieved, or quotes a
passage that does not appear in that source gets rejected rather than displayed.
Validation failure is a visible state, not a silently prettier answer.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

# --------------------------------------------------------------------------- #
# Controlled vocabularies.
#
# Version 1 ships four categories. The category -> team mapping is held in
# configuration (data/synthetic/categories.yaml), never produced by a model:
# a model that can invent a queue name can route a ticket into a queue that
# does not exist.
# --------------------------------------------------------------------------- #

Category = Literal[
    "account_access",
    "email",
    "vpn_connectivity",
    "software_installation",
]

AnalysisStatus = Literal[
    "ready_for_review",   # a draft is available
    "needs_information",  # answerable in principle, missing facts from the reporter
    "no_answer",          # the corpus does not support an answer
    "failed",             # the pipeline errored; nothing is presented as complete
]

ReviewAction = Literal["accepted", "edited", "rejected"]


# --------------------------------------------------------------------------- #
# Ticket intake
# --------------------------------------------------------------------------- #

class TicketCreate(BaseModel):
    """Creation-time fields only.

    There is no field here for a resolution or a final team, and that is the
    point: the intake contract makes it structurally impossible to submit a
    ticket carrying its own answer.
    """

    model_config = ConfigDict(extra="forbid")

    subject: str = Field(min_length=1, max_length=400)
    description_at_creation: str = Field(min_length=1, max_length=20_000)
    service: str | None = Field(default=None, max_length=200)
    impact_facts: dict[str, str | int | bool] = Field(default_factory=dict)
    is_synthetic: bool
    source_batch: str = Field(min_length=1, max_length=100)


class TicketOut(BaseModel):
    ticket_id: str
    subject: str
    description_at_creation: str
    service: str | None
    impact_facts: dict[str, str | int | bool]
    created_at: datetime
    is_synthetic: bool


# --------------------------------------------------------------------------- #
# Retrieval and evidence
# --------------------------------------------------------------------------- #

class Evidence(BaseModel):
    """One retrieved passage, carrying the identity needed to check it."""

    model_config = ConfigDict(extra="forbid")

    source_id: str
    version: int
    title: str
    passage: str
    available_at: datetime
    score: float


class Citation(BaseModel):
    """A claim in the draft, tied to the passage that supports it."""

    model_config = ConfigDict(extra="forbid")

    claim: str = Field(min_length=1)
    source_id: str
    version: int
    passage: str = Field(min_length=1)


# --------------------------------------------------------------------------- #
# Model output contract
# --------------------------------------------------------------------------- #

class DraftOutput(BaseModel):
    """Exactly what the generation step must return.

    Note what is absent: the model does not choose the team, the priority or
    whether to send anything. It drafts text and cites its sources. Routing
    comes from the classifier plus a versioned mapping; priority comes from an
    approved impact/urgency matrix; sending is a human action.
    """

    model_config = ConfigDict(extra="forbid")

    status: Literal["supported", "needs_information", "no_answer"]
    draft: str = ""
    questions: list[str] = Field(default_factory=list)
    citations: list[Citation] = Field(default_factory=list)
    reason: str = Field(min_length=1)

    @field_validator("draft")
    @classmethod
    def _draft_present_when_supported(cls, v: str, info) -> str:
        if info.data.get("status") == "supported" and not v.strip():
            raise ValueError("status 'supported' requires a draft")
        return v

    def check_against_retrieved(self, retrieved: list[Evidence]) -> None:
        """Reject citations the retrieval step never returned.

        An identifier check is necessary but not sufficient — it proves the
        source was retrieved, not that the passage supports the claim. Passage
        verification against the stored source text happens in the validation
        layer; claim support is scored by a human during evaluation.
        """
        allowed = {(e.source_id, e.version) for e in retrieved}
        for citation in self.citations:
            if (citation.source_id, citation.version) not in allowed:
                raise ValueError(
                    f"cited source {citation.source_id}:v{citation.version} "
                    "was not in the retrieved set"
                )
        if self.status == "supported" and not self.citations:
            raise ValueError("status 'supported' requires at least one citation")


# --------------------------------------------------------------------------- #
# Analyses and review
# --------------------------------------------------------------------------- #

class AnalysisOut(BaseModel):
    analysis_id: str
    ticket_id: str
    suggestion_version: int
    status: AnalysisStatus
    suggested_category: Category | None
    suggested_team: str | None
    confidence: float | None
    priority: str | None
    draft: str | None
    citations: list[Citation]
    questions: list[str]
    reason: str | None
    evidence: list[Evidence]
    # Everything needed to reproduce this exact result.
    classifier_version: str | None
    model_version: str | None
    prompt_version: str | None
    corpus_version: str | None
    created_at: datetime


class ReviewCreate(BaseModel):
    """An engineer's decision on one specific suggestion version.

    `suggestion_version` is mandatory. If it does not match the stored version
    the write is rejected with 409 and the UI is told to refresh — a reviewer
    must never approve a draft that has since been regenerated.
    """

    model_config = ConfigDict(extra="forbid")

    suggestion_version: int
    action: ReviewAction
    edited_text: str | None = None
    corrected_category: Category | None = None
    corrected_team: str | None = None
    reason: str | None = None

    @field_validator("edited_text")
    @classmethod
    def _edit_requires_text(cls, v: str | None, info) -> str | None:
        if info.data.get("action") == "edited" and not (v and v.strip()):
            raise ValueError("action 'edited' requires edited_text")
        return v


class ReviewOut(BaseModel):
    review_id: str
    analysis_id: str
    suggestion_version: int
    reviewer_id: str
    action: ReviewAction
    edited_text: str | None
    corrected_category: Category | None
    corrected_team: str | None
    reason: str | None
    created_at: datetime
