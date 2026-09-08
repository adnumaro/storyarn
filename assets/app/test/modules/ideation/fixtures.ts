import type { Board, Idea, Round } from "@modules/ideation/types";

export function idea(overrides: Partial<Idea> = {}): Idea {
  return {
    id: 10,
    round_id: null,
    late_contribution: false,
    session_id: 1,
    author_id: 1,
    author_kind: "human",
    title: "A motive",
    body: "<p>Original text</p>",
    preview: "Original text",
    state: "active",
    revision: 1,
    visibility: "private",
    published_revision: null,
    current_revision: 1,
    has_unpublished_changes: true,
    publication_consent: "author_only",
    configuration_version: 1,
    source_idea_id: null,
    source_revision: null,
    inserted_at: "2026-09-07T10:00:00Z",
    ...overrides,
  };
}
export function board(overrides: Partial<Board> = {}): Board {
  return {
    epoch: "epoch-one",
    loading: false,
    error: null,
    sessions: [],
    sessions_next: null,
    session_before: null,
    session_status: "open",
    session: {
      id: 1,
      title: "Character motives",
      objective: null,
      context: null,
      status: "open",
      revision: 1,
      configuration_version: 1,
      facilitator_id: 1,
      decision_owner_id: 1,
      deleted_at: null,
      inserted_at: "2026-09-07T10:00:00Z",
      can_manage: true,
      configuration: {
        private_mode: false,
        default_visibility: "private",
        publication_policy: "author_only",
      },
    },
    session_missing: false,
    rounds: [],
    rounds_next: null,
    active_round: null,
    round_filter: "all",
    ideas: [idea()],
    ideas_next: null,
    idea_before: null,
    counts: { active: 1, parked: 0, discarded: 0 },
    can_edit: true,
    can_manage: true,
    is_owner: true,
    current_user_id: 1,
    members: [{ id: 1, display_name: "Alex", avatar_url: null }],
    ...overrides,
  };
}

export function round(overrides: Partial<Round> = {}): Round {
  return {
    id: 20,
    session_id: 1,
    number: 1,
    prompt: "What motivates this character?",
    status: "active",
    started_at: "2026-09-08T10:00:00Z",
    closed_at: null,
    inserted_at: "2026-09-08T09:00:00Z",
    updated_at: "2026-09-08T10:00:00Z",
    ...overrides,
  };
}
