# Version Control — Epic Overview

## Vision

Build a version control system that gives narrative designers the safety and flexibility of Git without any of the technical complexity. Full project backups, entity-level history, private drafts, and intelligent auto-snapshots — all with zero friction.

**Core insight:** Designers don't want branches and commits. They want to feel safe: "I can experiment freely because I can always go back." Every decision in this system optimizes for that feeling.

## Why This Matters

Version control is one of the biggest pain points in narrative design tools:

| Tool             | What they offer                                                    | What's missing                                                     |
|------------------|--------------------------------------------------------------------|--------------------------------------------------------------------|
| **articy:draft** | SVN/Perforce partitions, rollback                                  | Binary diffs (useless), no branching, lock-based, Git blocked      |
| **Figma**        | Auto-save every 30min, named versions, branching (Enterprise only) | Branching paywalled, merge is all-or-nothing, no selective restore |
| **Notion**       | Auto-snapshot every 10min                                          | No diffs, no named versions, short retention, no branching         |
| **Google Docs**  | Per-keystroke OT, timeline, named versions                         | No branching, no structured data support                           |
| **Ink/Twine**    | Plain text → Git                                                   | Requires technical Git knowledge                                   |

**Storyarn's advantage:** We version **structured, relational data** (graphs, trees, entities with cross-references), not flat documents. This lets us build smarter tools: conflict detection on restore, change summaries that understand node/connection semantics, and eventually visual diffs on the canvas.

## Design Philosophy

1. **Zero friction for safety.** Auto-snapshots happen silently. The user never worries about losing work.
2. **Progressive depth.** Basic restore covers 80% of needs. Named versions, drafts, and project snapshots are there when needed.
3. **Honest about conflicts.** When restoring breaks references, we tell the user exactly what and let them decide. No silent data corruption.
4. **Complete backups.** A project snapshot contains EVERYTHING — entities, structure, images, audio. Delete the project, restore it whole from backup.

## Architecture

### Storage Strategy

**Two-tier storage** to keep PostgreSQL fast and costs low:

| Tier              | What                                                              | Where         | Why                              |
|-------------------|-------------------------------------------------------------------|---------------|----------------------------------|
| **Metadata**      | Version ID, entity ref, title, summary, author, date, storage key | PostgreSQL    | Fast queries, listing, filtering |
| **Snapshot data** | Full JSON + compressed assets                                     | Cloudflare R2 | Cheap, unlimited, no DB bloat    |

**Content-addressable asset storage:**
Assets (images, audio) stored by SHA256 hash. 50 snapshots referencing the same avatar = one copy in R2. Storage only grows when assets actually change.

```
projects/{project_id}/blobs/{sha256_hash}.{ext}        # Shared asset blobs
projects/{project_id}/snapshots/{entity_type}/{id}/{version}.json.gz  # Entity snapshots
projects/{project_id}/project_snapshots/{snapshot_id}.tar.gz          # Full project backups
```

### Retention Policy

| Plan       | Auto-snapshots   | Named versions   | Project snapshots  | Post-delete retention  |
|------------|------------------|------------------|--------------------|------------------------|
| Free       | 7 days           | 10               | 2                  | 30 days                |
| Pro        | 30 days          | 50               | 10                 | 90 days                |
| Team       | 90 days          | Unlimited        | 50                 | 1 year                 |
| Enterprise | Unlimited        | Unlimited        | Unlimited          | Indefinite             |

Expired snapshots cleaned by Oban job. Named versions never auto-expire.

## Epics

Each epic is self-contained. Within each epic, every feature is an independent unit with its own implementation plan.

### [Epic 1 — Entity Version History](./EPIC_1_ENTITY_VERSION_HISTORY.md)
> Per-entity snapshots, restore, and named versions for Sheets, Flows, and Scenes

| # | Feature                              | Standalone Value                                                                   |
|---|--------------------------------------|------------------------------------------------------------------------------------|
| 1 | Generalize versioning system         | Extend sheet versioning to Flows and Scenes with shared infrastructure             |
| 2 | Auto-snapshots by significant action | Automatic safety net — never lose more than 15 minutes of work                     |
| 3 | Named versions with intent           | User-created milestones with title, description, and auto-generated change summary |
| 4 | Restore with conflict detection      | Safe restore that validates cross-entity references before applying                |
| 5 | Content-addressable asset storage    | Assets in snapshots without storage explosion                                      |

### [Epic 1B — Version Changelog & Diff Summaries](./EPIC_1B_VERSION_CHANGELOG.md)
> Structured change summaries between versions — understand what changed at each point in history

| # | Feature                                  | Standalone Value                                                              |
|---|------------------------------------------|-------------------------------------------------------------------------------|
| 1 | Snapshot diff engine                     | Compare two snapshots and produce a structured list of semantic changes       |
| 2 | Auto-generate change summary on creation | Every version automatically describes what changed vs. the previous version   |
| 3 | Changelog display in Version History UI  | Version list shows readable changelogs instead of opaque timestamps           |
| 4 | Version comparison (pick two)            | Select any two versions and see what changed between them                     |

### [Epic 2 — Project Snapshots](./EPIC_2_PROJECT_SNAPSHOTS.md)
> Complete project backups that capture absolutely everything

| # | Feature                             | Standalone Value                                           |
|---|-------------------------------------|------------------------------------------------------------|
| 1 | Manual project snapshots            | One-click full backup of the entire project                |
| 2 | Automatic daily snapshots           | Background job creates daily backups when changes exist    |
| 3 | Project restore with exclusive lock | Safe full-project restoration with collaborator protection |
| 4 | Deleted project recovery            | Restore a deleted project entirely from its backup         |
| 5 | Project snapshot export             | Download a self-contained archive of the entire project    |

### [Epic 3 — Drafts](./EPIC_3_DRAFTS.md)
> Private workspaces for experimentation without risk

| # | Feature                    | Standalone Value                                  |
|---|----------------------------|---------------------------------------------------|
| 1 | Create draft from entity   | Fork a flow/sheet/scene into a private workspace  |
| 2 | Edit draft independently   | Full editing capabilities in isolation            |
| 3 | Draft review and merge     | Compare draft to current state, accept or discard |
| 4 | Draft lifecycle management | List, rename, discard drafts with cleanup         |

### Future: Visual Diffs (not planned yet)
> Side-by-side comparison on the canvas — nodes colored by change type

This is a killer feature that will be designed and built after the foundation (Epics 1-3) is solid. The architecture in Epics 1-3 is designed with visual diffs in mind: snapshots capture full state including positions, making canvas-level comparison possible.

## Execution Strategy

1. **Epic 1 first.** Entity versioning is the foundation everything else depends on.
2. **Epic 2 second.** Project snapshots build on entity snapshots + add the packaging layer.
3. **Epic 3 third.** Drafts are the most complex (copy + isolated editing + merge) but also the most differentiating.
4. **Plan per feature.** Each numbered feature gets its own implementation plan when it's time to build.
5. **Migrate existing sheet versioning.** Epic 1.1 refactors the current sheet-only system into the shared infrastructure, then extends it.

## Technical Foundation (existing)

| System                  | How it supports versioning                                    |
|-------------------------|---------------------------------------------------------------|
| **Sheet Versioning**    | Working snapshot/restore system to generalize                 |
| **R2 Storage**          | Already configured for asset storage — extend for snapshots   |
| **Oban**                | Job infrastructure for auto-snapshots, daily backups, cleanup |
| **PubSub**              | Broadcast restore events to collaborators                     |
| **Collaboration locks** | Foundation for exclusive restore mode                         |
| **Soft delete**         | Projects already soft-delete — snapshots survive deletion     |

## Cross-Entity Reference Strategy

The hardest problem in versioning relational data. Our approach:

**On snapshot creation:** Capture the entity state + record external references (sheet IDs, flow IDs, variable references) as metadata.

**On restore (Validation Strategy):**
1. Scan all external references in the snapshot
2. Check each against current state: does this sheet still exist? Does this flow still exist?
3. If broken references found → show conflict report to user before restoring
4. User chooses: restore with broken references cleaned, or cancel
5. Shortcut collisions (restored entity has a shortcut now used by another) → auto-rename with notification

**Future (with visual diffs):** Show broken references highlighted in the diff view so the user can see exactly what will break.
