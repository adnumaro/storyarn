# Ideas and explicit publication — ENG-132 / ENG-133

This delivery builds on the merged session foundation. It does not enable the
board or introduce private assets, AI execution, comments, notifications, global
search, exports or project recovery. ENG-134 owns the UI; ENG-129 and ENG-147 remain
release gates before accepting user content through that UI.

## Implementation

1. Add an Ideas capability with bounded rich text, immutable revisions, author
   identity, independent creative state and attributed derivation.
2. Keep the current draft separate from the last published revision. Readers,
   history queries and future adapters receive authorized projections only.
3. Persist save receipts and conflicting input so reconnects and retries cannot
   silently overwrite an edit or lose the losing contribution.
4. Capture publication consent against the configuration the contributor saw.
   A later session setting cannot broaden consent on existing contributions.
5. Prepare a durable reveal manifest of exact idea/revision pairs; execute it
   atomically with current permissions. Late ideas are excluded. A stale member
   rejects the entire operation. Retrying returns the original result.
6. Emit content-free invalidations only after the owning transaction commits.
   Private changes go only to the author's topic; public changes invalidate the
   shared session. Nested command transactions are rejected.

## Boundaries

- Sessions owns project authorization and the locked session lifecycle check.
  Ideas enters through its capability facade and owns all idea persistence.
- Only authors edit text or creative state. Developing somebody else's visible
  idea creates a new attributed idea. Facilitators/owners can publish only the
  contributions that explicitly accepted assisted publication.
- Readers never receive unpublished text, save attempts or draft revision
  numbers belonging to others. Archived sessions remain readable but immutable.
- Content is encrypted at rest and redacted from Ecto inspection. Operational
  recovery is privileged infrastructure, not a project-owner read permission.
- Private attachment ingestion and external references remain unavailable.
  Derivation references an authorized immutable idea revision in the session.
- No hard-delete or retention timer is introduced. Project deletion cascades;
  loss of access denies reads; account deletion never transfers private drafts.

## Validation

Use a fresh isolated database and focused tests for the permission matrix,
validation, retries, retained conflicts, immutable publications, policy changes,
derivation, lifecycle and real concurrent transactions. Extend architecture and
facade contracts. Run the repository formatting checks and full precommit gate,
then verify the published commit's CI. Aim to keep the PR below 8,000 changed lines.
