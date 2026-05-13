# Flow Player Sequence Stage Composition

Date: 2026-05-13

## Goal

Turn flow sequences into a lightweight visual-novel staging system:

- Designers can draft a scene with layered visuals: backdrop, characters, props, overlays.
- Designers can attach sequence-level sound: music, ambience, and later short SFX.
- Nested sequences compose from parent to child, so broad context is defined once and inner beats add or override details.
- The player renders a close approximation of the intended visual-novel experience without requiring a game engine.

This is not a backward-compatible migration. The current sequence media model is local-only and can be replaced cleanly.

## Current Audit

Current implementation is useful as a spike, but the public concept is wrong:

- `flow_node_sequence_configs` stores one `background_asset_id`, `background_position`, and `background_fit`.
- `FlowSequenceConfigPanel.vue` exposes "Background image" and three audio slots.
- `PlayerLive` serializes `backgrounds` from the active sequence chain.
- `FlowPlayer.vue` renders those backgrounds as stacked images.
- `SequenceTrack` exists for sequence audio with `background | music | ambient` kinds.

Problem:

- A character sprite is not a background.
- `cover | contain | fill` is not enough to stage character proportions.
- The UI does not tell the designer whether an asset is a full-screen stage, a character, an overlay, or a prop.
- Audio kind `background` is ambiguous now that visual backgrounds also exist.

Decision:

- Replace "sequence background" with explicit `sequence visual layers`.
- Keep sequence nesting as the composition mechanism.
- Keep sequence-level audio, but rename semantics around audio kinds.

## Target Mental Model

Sequence = stage context.

Parent sequence:

- full scene backdrop
- base music
- base ambience

Child sequence:

- character appears
- character changes pose/expression
- overlay/effect
- additional ambience or music change

Node:

- dialogue text
- choices
- instructions
- later: voice line / per-line audio

## Target Data Model

### Sequence Config

`flow_node_sequence_configs` should stay focused on sequence metadata:

- `flow_node_id`
- `name`
- `width`
- `height`

Remove from this table:

- `background_asset_id`
- `background_position`
- `background_fit`

### Sequence Visual Layers

New table: `flow_node_sequence_visual_layers`.

Suggested fields:

- `id`
- `flow_node_id` - sequence node id
- `asset_id`
- `kind` - `backdrop | character | prop | overlay`
- `label`
- `z_index`
- `slot` - preset id, e.g. `full | left | center | right | custom`
- `x` - normalized stage coordinate, 0..1
- `y` - normalized stage coordinate, 0..1
- `width` - normalized stage width, 0..1
- `height` - normalized stage height, 0..1
- `anchor_x` - normalized anchor, 0..1
- `anchor_y` - normalized anchor, 0..1
- `fit` - `cover | contain | fill`
- `opacity` - default 1.0
- `visible` - default true
- timestamps

Default presets:

- Backdrop: `slot=full`, `x=0`, `y=0`, `width=1`, `height=1`, `anchor_x=0`, `anchor_y=0`, `fit=cover`.
- Character left: `x=0.25`, `y=1`, `width=0.38`, `height=0.9`, `anchor_x=0.5`, `anchor_y=1`, `fit=contain`.
- Character center: `x=0.5`, `y=1`, `width=0.42`, `height=0.92`, `anchor_x=0.5`, `anchor_y=1`, `fit=contain`.
- Character right: `x=0.75`, `y=1`, `width=0.38`, `height=0.9`, `anchor_x=0.5`, `anchor_y=1`, `fit=contain`.
- Overlay: `slot=full`, same geometry as backdrop, `fit=cover`, `z_index` above characters by default.

Rationale:

- Normalized stage coordinates work across viewport sizes.
- Presets make the first version clear for users.
- Custom geometry keeps a path toward a future 2D engine.

### Sequence Audio Tracks

Current `flow_node_sequence_tracks` can stay, but kind names should be clarified:

- `music`
- `ambience`
- `sfx`

Avoid `background` as an audio kind because it conflicts with visual language.

Voice lines should not be sequence audio by default. They belong to dialogue nodes or dialogue lines, because timing follows text progression.

## Phase 0 - Focused Re-Audit Before Coding

Scope:

- Confirm all current references to sequence background fields.
- Confirm all current references to sequence tracks and audio kind strings.
- Confirm migrations and DB constraints that must be dropped.
- Confirm tests that encode `backgrounds` player props.

Files to audit:

- `lib/storyarn/flows/sequence_config.ex`
- `lib/storyarn/flows/sequence_track.ex`
- `lib/storyarn/flows/sequence_crud.ex`
- `lib/storyarn/flow*.ex`
- `lib/storyarn_web/live/flow_live/player_live.ex`
- `lib/storyarn_web/live/flow_live/handlers/generic_node_handlers.ex`
- `lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex`
- `assets/app/modules/flows/editor/components/panels/FlowSequenceConfigPanel.vue`
- `assets/app/live/flow/player/FlowPlayer.vue`
- `assets/app/modules/flows/player/components/PlayerAudioTracks.vue`
- `test/storyarn_web/live/flow_live/player/player_live_test.exs`
- `assets/app/test/modules/flows/player/FlowPlayer.test.ts`

Audit output:

- Exact list of fields/events/props to remove.
- Exact list of new contracts to introduce.
- Decision on whether to drop or recreate local data manually before testing.

Validation:

- No code changes yet.
- Plan updated if audit finds hidden coupling.

## Phase 1 - Data Model Reset

Goal:

- Remove the one-background-per-sequence model.
- Add visual layers as first-class sequence-owned records.
- Rename audio semantics if we decide to do that in this migration.

Backend work:

- Add `Storyarn.Flows.SequenceVisualLayer`.
- Add `has_many :sequence_visual_layers` to `FlowNode`.
- Add migration for `flow_node_sequence_visual_layers`.
- Drop `background_asset_id`, `background_position`, `background_fit` from `flow_node_sequence_configs`.
- Drop related indexes/check constraints.
- Update `SequenceConfig` changesets and moduledoc.
- Add CRUD helpers:
  - `list_sequence_visual_layers/1`
  - `create_sequence_visual_layer/3`
  - `update_sequence_visual_layer/2`
  - `delete_sequence_visual_layer/1`
  - optional reorder helper

Phase audit:

- Verify DB trigger/constraint pattern matches current sequence owner validation style.
- Verify asset foreign key deletion behavior. Suggested: `on_delete: :delete_all` or `:nilify_all` depending UX. Prefer `:nilify_all` only if UI handles missing assets clearly.
- Verify no remaining compile references to removed background fields.
- Verify `SequenceCrud.update_sequence/2` only updates sequence metadata, not visual media.

Validation:

- `mix test test/storyarn/flows/sequence_crud_test.exs`
- targeted compile via `mix test test/storyarn_web/live/flow_live/player/player_live_test.exs`

## Phase 2 - Player Contract

Goal:

- Replace `backgrounds` prop with `visualLayers`.
- Keep audio as separate `audioTracks`.
- Resolve nested sequence chain parent to child.

Backend work:

- Preload `sequence_visual_layers: [:asset]` in player/debug node maps.
- Serialize `visual_layers` with:
  - `id`
  - `sequence_id`
  - `sequence_depth`
  - `kind`
  - `label`
  - `url`
  - `z_index`
  - geometry fields
  - `fit`
  - `opacity`
- Sort by `{sequence_depth, z_index, id}`.
- Keep `audio_tracks` sorted by `{sequence_depth, kind_order, position, id}`.
- Rename player helper from `player_backgrounds/1` to `player_visual_layers/1`.

Phase audit:

- Verify active sequence chain is still cycle-safe.
- Verify parent layers render below child layers.
- Verify child sequence additions do not destroy parent context.
- Verify player props do not expose old background naming.

Validation:

- Player LiveView tests asserting:
  - no sequence -> `visualLayers: []`
  - parent backdrop + child character -> ordered layers
  - nested overlay above character
  - audio tracks still resolve parent to child

## Phase 3 - Player Rendering

Goal:

- Render the stage as actual `<img>` layers with explicit boxes.
- Avoid CSS background-image for assets.
- Avoid implicit opacity.

Frontend work:

- Add `PlayerVisualLayers.vue`.
- Each layer renders as:
  - wrapper box positioned in normalized stage space
  - `<img>` inside the box
  - `object-fit` from layer
  - `opacity` from layer, default 1
- `FlowPlayer.vue` consumes `visualLayers` and `audioTracks`.
- Rename CSS classes from generic `.player-backdrop` to stage-specific names:
  - `.flow-player-stage-layer`
  - `.flow-player-stage-layer-img`

Phase audit:

- Verify exploration mode does not share these classes.
- Verify no global CSS class affects scenes exploration.
- Verify character presets produce sane proportions at desktop and smaller widths.
- Verify transparent PNGs remain flat and are not darkened by parent opacity.

Validation:

- Vitest:
  - renders `<img>` layers
  - style geometry from normalized fields
  - `backdrop` uses cover
  - `character` uses contain and bottom anchor
- Browser manual:
  - route `/flows/:id/play`
  - one backdrop + one character
  - two nested sequences with parent/child layers

## Phase 4 - Editor Sequence Panel

Goal:

- Make sequence media setup understandable.
- Replace "Background image" with "Visual composition".

Frontend work:

- Rewrite `FlowSequenceConfigPanel.vue` around two sections:
  - `Visual composition`
  - `Sound`
- Add visual layer list:
  - label
  - kind
  - slot
  - thumbnail
  - reorder controls
  - remove
- Add "Add visual layer" flow:
  - choose asset
  - choose kind: Stage / Character / Prop / Overlay
  - choose preset slot
- Start with simple controls:
  - kind selector
  - slot selector
  - fit selector
  - size slider for character/prop
  - opacity slider
- Keep advanced free positioning for later unless needed immediately.

Backend work:

- Add LiveView events:
  - `create_sequence_visual_layer`
  - `update_sequence_visual_layer`
  - `delete_sequence_visual_layer`
  - `reorder_sequence_visual_layers`
- Update panel data builder to include visual layer list.
- Broadcast updates to collaborators.

Phase audit:

- Verify event names match existing flow handler style.
- Verify public Vue components still only live under `assets/app/live`.
- Verify no panel logic leaks into HEEx.
- Verify translations cover every visible label.

Validation:

- LiveView tests for events and panel data.
- Vitest for panel interactions.
- Manual browser:
  - create sequence
  - add backdrop
  - add character left/right
  - play route reflects composition

## Phase 5 - Audio Cleanup

Goal:

- Keep sequence-level sound clear and future-proof.

Work:

- Decide whether to rename `background` audio kind to `ambience` now.
- If yes:
  - update `SequenceTrack.kinds/0`
  - update DB constraint
  - update translations
  - update player kind ordering
  - update panel labels
- Keep voice out of sequence tracks for now.
- Later voice model should live on dialogue line/node, not sequence.

Phase audit:

- Verify no old `background` audio kind remains.
- Verify existing local data is not considered authoritative.
- Verify the player can play multiple sequence tracks without crashing if autoplay is blocked.

Validation:

- `mix test test/storyarn_web/live/flow_live/player/player_live_test.exs`
- `pnpm exec vitest run assets/app/test/modules/flows/player`

## Phase 6 - Local Data Reset And Manual Scenario

Goal:

- Recreate the local demo sequence data using the new model.

Manual scenario:

- Delete existing sequences in the local demo flow.
- Create parent sequence:
  - backdrop: industrial storm
  - music or ambience
- Create child sequence:
  - character Sera, left or center
  - optional overlay
- Put dialogue node inside child sequence.
- Open player and verify:
  - backdrop covers full stage
  - character is correctly proportioned
  - child layers render above parent layers
  - dialogue panel sits above visual stage
  - audio starts or retries after user gesture

Phase audit:

- Verify no stale rows remain in old sequence media columns/tables.
- Verify player receives `visualLayers`, not `backgrounds`.
- Verify local demo proves the intended user workflow.

Validation:

- Browser screenshots before/after.
- Console has no errors.

## Phase 7 - Cleanup And Architecture Checks

Goal:

- Remove transitional naming and stale tests.

Work:

- Remove old docs/comments that call character layers backgrounds.
- Update feature docs if needed.
- Update tests to reflect stage composition terminology.
- Consider `docs/features/flow-relational-refactor` addendum if the new model changes the sequence architecture contract.

Validation:

- `pnpm run fmt:check`
- `pnpm run lint`
- `pnpm run arch`
- `mix test test/storyarn/flows/sequence_crud_test.exs`
- `mix test test/storyarn_web/live/flow_live/player`
- Browser manual player check.

## Future Engine Path

Do not implement these now, but keep the data model compatible:

- Per-node layer overrides.
- Timed transitions: fade in/out, crossfade, slide.
- Character expression slots bound to sheets/characters.
- Voice lines attached to dialogue nodes.
- Timeline/keyframes for scene direction.
- Export stage composition to a future 2D runtime.
- Playable VN mode outside the editor route.

## First Implementation Recommendation

Start with Phase 0 and Phase 1 only.

Reason:

- The current issue is rooted in data semantics, not CSS.
- If we patch the player further before adding visual layers, we will keep encoding character logic into background fields.
- No backward compatibility requirement means the cleanest path is to replace the model first, then make the UI/player consume the new contract.
