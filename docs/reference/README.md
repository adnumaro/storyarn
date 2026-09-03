# Repository documentation

> Owner: Engineering
>
> Last reviewed: 2026-09-02
>
> Source of truth: this index

This directory contains only technical contracts and operational runbooks that
must change atomically with the code they describe.

## Documentation boundaries

- `docs/reference/` owns code-adjacent engineering contracts and runbooks.
- `priv/docs/` owns localized public product documentation.
- [Storyarn Internal Documentation](https://app.notion.com/p/3aab4dcc1285810a93dcc0f7150a2025)
  owns durable internal product, feature, architecture, and market documentation.
- Linear owns implementation tasks, roadmaps, and unresolved work.
- `docs/game_references/` is independently managed and explicitly excluded from
  this convention.

The two AI roadmap documents under `docs/features/ai-platform/` are temporary
exceptions retained by explicit product decision. Do not add new documents
beside them: new tasks belong in Linear and new code-adjacent references belong
in this directory.

## Convention

- Use lower-kebab-case filenames.
- Start every document with `Owner`, `Last reviewed`, and `Source of truth`.
- Document current contracts, not implementation checklists or future plans.
- Prefer links to authoritative code over duplicated inventories.
- Review a document in the same change that alters its contract.
- Move unfinished work to Linear before removing its planning document.

## Index

- [Component registry](component-registry.md)
- [Domain patterns](domain-patterns.md)
- [Bounded-context map](context-map.md)
- [Shared utilities](shared-utilities.md)
- [Flow dialogue typography](flow-dialogue-typography.md)
- [AI provider adapters](ai-provider-adapters.md)
- [AI operations](ai-operations.md)
- [Versioning containment](versioning-containment.md)
- [ENG-52 operational recovery validation](eng-52-operational-recovery-validation.md)
- [Entity-version restore integrity](entity-version-restore-integrity.md)
- [Ownership integrity preflight](ownership-integrity-preflight.md)
