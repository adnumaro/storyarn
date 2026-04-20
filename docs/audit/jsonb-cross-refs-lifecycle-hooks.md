# Tech Debt: JSONB cross-references without lifecycle hooks

**Severity:** Medium — data-integrity gap with silent failure modes.
**Found:** 2026-04-20, while designing `Storyarn.Flows.Sequence` (P-3 of flow-player-redesign).

## The pattern

Many schemas store references to other entities inside a JSONB `data` field rather than as explicit database columns with foreign keys. Examples:

| Source field                            | Target entity         | Location                    |
| --------------------------------------- | --------------------- | --------------------------- |
| `flow_nodes.data["speaker_sheet_id"]`   | `sheets.id`           | dialogue nodes              |
| `flow_nodes.data["audio_asset_id"]`     | `assets.id`           | dialogue nodes              |
| `flow_nodes.data["avatar_id"]`          | `sheet_avatars.id`    | dialogue + other nodes      |
| `flow_nodes.data["referenced_flow_id"]` | `flows.id`            | subflow + exit nodes        |
| `flow_nodes.data["target_hub_id"]`      | `flow_nodes.id` (hub) | jump nodes                  |
| `flow_nodes.data["sequence_directive"]` | `flow_sequences.id`   | executable nodes (post-P-3) |

This shape is **legitimate for this domain** — node data has widely different shapes per node type (dialogue has `responses[]`, condition has `cases[]`, jump has `target_hub_id`), and normalizing every variant into its own table would produce 15+ small tables for marginal semantic gain. This is how comparable narrative-design tools (Articy, Yarn Spinner, Ink) structure their data too.

## The gap

When the **target** entity is deleted, the pointer is **silently orphaned**. Postgres FK cascade does not apply because there is no FK (JSONB fields cannot carry FK constraints).

Current state:

- ✅ Permissive persistence (no validation at save time — consistent with the domain's flexibility)
- ✅ `Storyarn.Exports.Validator` surfaces broken refs at export time (`check_broken_jump_refs`, `check_broken_subflow_refs`, etc.)
- ❌ **No lifecycle hook at target deletion**. When a Sheet, Asset, Flow, Hub, or (new) Sequence is deleted, nothing cleans up the JSONB pointers that referenced it. Orphans accumulate silently until the next export surfaces them.

## Why the validator is not enough

1. **Timing.** Orphans sit in the DB between "target deleted" and "user runs validator/exports". In that window, player runtime, render helpers, and every consumer has to defensively check `if (speaker_sheet_id && sheets[id]) …`.
2. **N defensive copies.** Every consumer (render, validator, editor UI, player slide builder) re-implements the "what if the target is gone" branch. That's where bugs hide.
3. **The validator is reactive, not proactive.** Nothing prevents orphans from being created; the validator only reports them later. Users can live with broken references indefinitely if they never run the exporter.

## Proposed remediation pattern

For each target entity that is referenced via JSONB cross-refs, add a lifecycle hook at deletion that either:

- **Blocks deletion** with a helpful error ("X nodes reference this Sheet — remove those references first"), OR
- **Sweeps pointers** — walk the referencing tables and nullify/remove the JSONB key.

Both options keep the data clean without re-architecting the JSONB shape.

`Storyarn.Shared.SoftDelete.soft_delete_children/3-4` already accepts a `pre_delete:` callback hook; use that convention for any entity that soft-deletes.

### Example (Sequence — to be shipped alongside this doc)

```elixir
# In Storyarn.Flows.SequenceCrud
def delete_sequence(%Sequence{} = sequence) do
  Repo.transaction(fn ->
    # 1. Soft-delete the sequence
    {:ok, deleted} = sequence |> Sequence.soft_delete_changeset() |> Repo.update()

    # 2. Sweep: nullify sequence_directive in nodes of the same flow
    clear_sequence_directive_pointers(deleted.flow_id, deleted.id)

    deleted
  end)
end
```

## Remediation priority

Not a blocker for pre-release, but each new cross-ref added without a lifecycle hook is new debt. Prioritize:

1. **On any new JSONB cross-ref, add the hook upfront.** Start with `sequence_directive` (Sequence delete → clear pointers) as part of P-3.
2. **Retrofit high-impact ones next.** Asset and Sheet deletions are the most likely to strand orphans at scale.
3. **Low-impact ones can wait.** `target_hub_id` (jump → hub) is already surfaced by validator and hubs are rarely deleted.

## Entity-level audit

Inventory to complete once someone has bandwidth. Each row should confirm: is a lifecycle hook wired? If not, note severity.

| Target              | Source cross-refs                                     | Current hook                                   | Action       |
| ------------------- | ----------------------------------------------------- | ---------------------------------------------- | ------------ |
| `sheets`            | `speaker_sheet_id`, `avatar_id` (via `sheet_avatars`) | ❌                                             | retrofit     |
| `assets`            | `audio_asset_id`                                      | ❌                                             | retrofit     |
| `sheet_avatars`     | `avatar_id`                                           | ❌                                             | retrofit     |
| `flows`             | `referenced_flow_id` (subflow/exit)                   | ❌                                             | retrofit     |
| `flow_nodes` (hubs) | `target_hub_id` (jumps)                               | ❌ (validator only)                            | low priority |
| `flow_sequences`    | `sequence_directive`                                  | ✅ (P-3, see `SequenceCrud.delete_sequence/1`) | done         |

## Why this is recorded here

The user asked, while designing Sequence delete semantics: _"Crees que la app debería de ser así? lo que estamos haciendo es un anti patrón?"_ — honest answer: the **shape** (JSONB cross-refs) is legitimate; the **handling** is incomplete. Recording it here prevents the issue from getting lost in a commit message and gives future retrofits a checklist.
