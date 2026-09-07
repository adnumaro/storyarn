# Flow sequence composition

> Owner: Flows
>
> Last reviewed: 2026-09-06
>
> Source of truth: this contract

This contract defines the static composition shown for every narrative
intervention in the Sequence workspace, inline playback, and Debug. An intervention is a
`dialogue` node; its speaker, text, direction, and localized voice remain
dialogue data.

## Workspace contract

Flows open with the full node canvas. The dock Play control opens the visual
workspace above it and becomes Stop. Stop closes the workspace and discards
its ephemeral playback session. The divider resizes both views; fullscreen
expands the existing workspace without navigation. There is no standalone
Player route.

New authoring uses dialogue-owned compositions. Sequence container records
remain readable for compatibility with existing projects and snapshots; the
node palette does not offer a new Sequence node.

Images are clipped to the 16:9 frame. Selection outlines and resize handles
remain outside that clipping surface. Normalized geometry is shared by the
editor and playback. Newly added layers go in front; an explicit
`composition_layer_order` stores local changes to the effective order without
rewriting ancestor layers. Source changes reconcile that order.

The library uses project Assets and Sheet imagery. Uploads follow the shared
original/optimized-image decision flow. The library shows one image per
original/web family, choosing the lighter file; cropped derivatives remain
separate images. Uploaded assets stay in the project if the user leaves the
intervention before attachment completes.

## Ownership and source chains

- Only `sequence` and `dialogue` nodes own compositions.
- `composition_source_id` is an explicit nullable reference to another
  composition owner in the same Flow. It is separate from `parent_id`, graph
  connections, and execution history.
- `composition_source_id: null` means a root composition whose inherited input
  is empty. It never means “use the containing sequence” or “use the previously
  executed dialogue.”
- A source must exist, be active, belong to the same Flow, and be either a
  `sequence` or `dialogue`. Source chains must be acyclic.
- A source is a composition dependency, not an execution dependency. It need
  not be connected to, precede, or be reachable from its owner.
- Resolution walks the source chain from root to the selected owner. The result
  therefore depends only on persisted composition data, regardless of the path
  used to reach or preview the node.
- Moving a node on the canvas or changing `parent_id` does not rewrite its
  composition source. Deleting a referenced source is rejected; its dependents
  must first be reassigned explicitly.

Existing sequence behavior is preserved once, during migration, by copying the
nearest containing sequence relationship into `composition_source_id` for
existing sequence and dialogue owners. After that migration the two
relationships evolve independently.

## Layers and local changes

Every visual layer has a stable logical identity across its source chain. A
composition stores only its local changes and resolves them over the effective
source composition.

For each property, including the asset, kind, placement, size, anchor, fit,
z-order, opacity, and visibility, these states are distinct:

| State        | Persisted meaning                                | Effective result                                     |
| ------------ | ------------------------------------------------ | ---------------------------------------------------- |
| Inherit      | No local value for the property                  | Use the source value                                 |
| Override     | Store the property in the local override set     | Use the local value, including `false` or `0`        |
| Revert       | Remove that property from the local override set | Reveal the source value again                        |
| Remove layer | Store a tombstone for the logical layer          | Omit the layer from this composition and descendants |

Reverting a tombstone removes the local tombstone and reveals the source layer.
Removing a layer introduced by the same composition deletes that local layer;
it does not create a tombstone because there is no inherited layer to suppress.
A new layer receives a new logical identity and a complete valid initial value.
A meaningless tombstone for an identity absent from the source chain is
invalid. A descendant can restore a tombstoned identity only by supplying a
complete local layer, because there is no effective value for partial overrides.

Music, ambience, and SFX follow the same rules, using a stable track key as their
logical identity. The kind labels the channel but does not collapse legacy
tracks that already compose additively across nested sequences. No local track
change means continuity from the source; overrides can replace its asset or
settings; reverting reveals the source; and a tombstone means explicit silence
for that track. Dialogue voice is not a composition channel.

## Branches and convergence

A `condition` node chooses a graph route and owns no composition. Different
staging, expression, direction, tone, or voice is represented by distinct
`dialogue` nodes. Those dialogues may contain the same text and may share one
explicit composition source.

A dialogue after a convergence also has one explicit source. It never inherits
from whichever branch happened to execute last, so the same node resolves to
the same composition from every incoming route.

## Required examples

### Linear flow

`Base` is a root dialogue with backdrop `room` and music `theme`. `Greeting`
sources `Base` and adds character `Ada`. `Reply` sources `Greeting` and
overrides only Ada's expression asset. Changing the backdrop on `Base`
propagates to both dialogues. Reverting the expression on `Reply` reveals the
asset from `Greeting`; tombstoning Ada on `Reply` removes her there.

### Branch and merge

`Condition` routes to `Friendly` or `Hostile`. Both source `Base`, but each has
its own character and localized voice changes. `Aftermath`, where the graph
merges, also sources `Base`. Its composition is identical after either branch;
it does not inspect the preceding dialogue.

### Loop

The execution graph may loop from `Reply` back to `Greeting`, while the source
chain remains `Base <- Greeting <- Reply`. Re-entering `Greeting` resolves
`Greeting` again and does not accumulate changes from `Reply`. A source chain
`Greeting <- Reply <- Greeting` is rejected as a cycle even when the execution
graph loop itself is valid.

### Jump or Flow boundary

Jumping to a dialogue resolves that target's declared source chain. No
composition state travels with the jump. A source cannot cross a Flow boundary;
entry into another Flow starts from the target Flow's own declared composition.

### Isolated preview

Previewing a selected dialogue resolves only its persisted source chain. The
last node previewed, canvas containment, and an unexecuted incoming branch have
no effect. A missing or cyclic source produces a diagnostic instead of a
fallback composition.

### Back and restart

Back restores the previous renderable node and recomputes that node's
composition from its source chain; it does not reverse deltas or retain changes
from the node being left. Restart clears the run and resolves the first
renderable node in the same way. Repeated back, restart, loop, and re-entry
operations never accumulate composition state.

## Audio advance

Manual continue moves immediately to the next intervention and stops the prior
dialogue voice, whether that voice is active, finished, or absent. It does not
wait for audio completion and does not require a second action.

The next dialogue uses the voice for its active locale. An unchanged effective
music or ambience channel continues without restarting. A replaced or
tombstoned channel switches or stops immediately. There are no fades or timed
transitions in this contract.

## Capability matrix

| Capability              | Editor and isolated preview                                           | Player                                                              | Debug                                                         |
| ----------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------- |
| Resolve source chain    | Shows the selected owner's effective composition and property origins | Renders the same effective composition                              | Reports the same values, origins, overrides, and tombstones   |
| Condition branch        | Edits each destination dialogue independently                         | Existing Flow evaluation chooses the dialogue                       | Existing evaluator shows the chosen route and its composition |
| Convergence, loop, jump | Preview remains independent of selection history                      | Recomputes the destination owner without accumulated state          | Matches Player for step, back, reset, and re-entry            |
| Local changes           | Persists inherit, override, revert, and remove as distinct actions    | Applies the resolved result                                         | Identifies which owner supplies every effective property      |
| Dialogue voice          | Previews the voice for the active locale                              | Cuts the prior voice on continue and starts the next when available | Exposes the selected localized voice and playback decision    |
| Music and ambience      | Previews effective channels                                           | Preserves unchanged channels; switches or stops changed ones        | Exposes effective channel identity and origin                 |

## Comments, locales, and history

Sequence comments reuse Flow node threads through `presentation: workspace`.
They are anchored to the dialogue, not to a temporary layer row or pixel.
Opening the same thread from Flow preserves messages, mentions, permissions,
resolution and revisions. Fullscreen does not create another discussion.

The content locale is session presentation state, separate from the interface
language and authored data. Missing translated fields visibly fall back to
source text. Missing, stale or unapproved target voice never falls back to the
source recording. Active locale is retained through inline continue, back,
restart and subflow traversal.

Composition undo format 2 captures audio as well as source, geometry, layer
order and visual changes. Format 1 entries without tracks preserve current
audio under the owner lock. Format 2 requires an explicit track list. Restores
validate inherited track kinds and compare the expected current state to
avoid overwriting another editor's work.

Background tracks use stable asset continuity keys. Volume-only changes do
not restart playback. SFX and dialogue voice play once; music and ambience
loop. Continue interrupts voice immediately. Restart resets audio; closing
or stopping playback stops its media elements. Blocked autoplay exposes an
explicit retry control.

## Persistence and export

Flow versions and Storyarn project snapshots preserve
`composition_source_id`, visual layers, audio tracks, stable logical keys,
property override masks, and tombstones. Restoring through these native paths
remaps composition owners and asset references together, so they are the
round-trip formats for this feature.

The Ink, Yarn Spinner, Unity, Godot Dialogic, Unreal, and articy:draft
exporters preserve the narrative data they already support, but they cannot
represent Storyarn's static sequence composition. Their pre-export validation,
which is enabled by default, emits one `unsupported_sequence_composition`
warning for every selected Flow that contains a composition source, visual
layer, or audio track. The warning identifies the Flow and format before the
export omits those composition details. Use a Storyarn project snapshot when
the composition must survive a round trip.

## Exclusions

- Animations, animated transitions, timeline, keyframes, durations, easing, and
  video.
- Image conditions or mutually exclusive visual variants inside one dialogue;
  use `Condition` and distinct dialogues.
- Implicit inheritance from `parent_id`, graph adjacency, execution order, or
  the last previewed node.
- Progressive text reveal, waits tied to voice completion, and double-action
  advance.
- New SFX timing, clip trimming, or other animation-ready infrastructure. The
  existing SFX data is not removed by this contract.
