# Unity Dialogue System JSON Reimplementation Plan

## Context

Storyarn currently exposes a `:unity` export format through
`Storyarn.Exports.Serializers.UnityJSON`, but the emitted JSON is not shaped like
Pixel Crushers Dialogue System for Unity's JSON import/export format. The current
serializer uses a custom envelope:

- `format`
- `storyarn_version`
- `database.actors`
- `database.conversations`
- `database.variables`

Dialogue System expects a DialogueDatabase JSON document with top-level database
collections and asset-style records:

- `version`
- `author`
- `description`
- `globalUserScript`
- `emphasisSettings`
- `actors`
- `items`
- `locations`
- `variables`
- `conversations`
- `syncInfo`
- `templateJson`

Actors, variables, conversations, and dialogue entries are field-driven. They use
lists of field objects with `title`, `value`, `type`, and `typeString`.
Conversations contain `dialogueEntries`, and entries link through
`outgoingLinks`, not Storyarn node ids.

Primary references:

- <https://www.pixelcrushers.com/dialogue_system/manual2x/html/json.html>
- <https://www.pixelcrushers.com/dialogue_system/manual2x/html/cutscene_sequences.html>

## Goals

- Emit a JSON shape that Dialogue System for Unity can import.
- Preserve Storyarn flow semantics where Unity has an equivalent concept.
- Keep Storyarn-only metadata available as custom fields, not arbitrary top-level
  keys that Dialogue System does not understand.
- Build robust tests around the external contract instead of current internal
  placeholder keys.
- Keep implementation aligned with existing export modules and expression
  transpiler helpers.

## Non-Goals For The First Pass

- Do not implement a Unity-side runtime package.
- Do not invent custom Unity sequencer commands unless explicitly needed later.
- Do not force Storyarn sequence visual layers/audio tracks into invalid Unity
  commands.
- Do not treat this as a full round-trip importer. This is export-first.

## Current Gaps

### Invalid JSON Shape

`UnityJSON.serialize/2` builds a custom `"database"` object. Pixel Crushers
expects the database collections at the root.

### Wrong Asset Representation

Actors and variables are emitted as direct maps:

- actor `name`
- actor `shortcut`
- actor `fields` as a map
- variable `name`
- variable `type`
- variable `initial_value`

Dialogue System expects field arrays such as:

- `Name`
- `Display Name`
- `IsPlayer`
- `Initial Value`
- custom Storyarn fields where useful

### Wrong Conversation Representation

The current serializer uses `entries`; Dialogue System expects
`dialogueEntries`. Conversation records should be assets with fields and
additional dialogue-specific properties.

### Broken Link Semantics

The current `links_to` values are Storyarn node ids. Dialogue System
`outgoingLinks` must reference dialogue entry ids inside conversation ids:

- `originConversationID`
- `originDialogueID`
- `destinationConversationID`
- `destinationDialogueID`
- `isConnector`
- `priority`

### Incomplete Storyarn Feature Mapping

The current fallback keeps unsupported nodes as base entries. This loses
semantics for:

- `hub`
- `jump`
- `subflow`
- `exit`
- `sequence`
- condition switch branches
- response branch bodies
- localization fields
- dialogue audio / Unity Sequence field

## Proposed Architecture

### Serializer Shape

Keep `Storyarn.Exports.Serializers.UnityJSON` as the public serializer module,
but split implementation internally into small helpers:

- `build_database/2`
- `build_actors/2`
- `build_variables/1`
- `build_conversations/3`
- `build_dialogue_entries/4`
- `field/4`
- `text_field/2`
- `number_field/2`
- `boolean_field/2`
- `actor_ref_field/2`
- `asset/2`
- `dialogue_entry/1`
- `outgoing_link/6`

If the module becomes too large after the first implementation, extract a
dedicated helper module under `lib/storyarn/exports/serializers/unity_json/`.
Do not do that extraction before there is real pressure from size or tests.

### ID Strategy

Dialogue System ids are integer ids scoped by collection.

- Actor ids: sequential integers from exported sheets.
- Conversation ids: sequential integers from exported flows.
- Dialogue entry ids: sequential integers per conversation.

Build a per-flow planning structure before rendering entries:

- Storyarn node id -> dialogue entry id
- Storyarn response id -> dialogue entry id
- synthetic ids for branch/instruction/pass-through entries where needed

Avoid using raw Storyarn DB ids as Dialogue System ids unless a test proves it is
valuable. Sequential ids produce cleaner imports and match the documented
examples.

Preserve Storyarn ids in custom fields:

- `Storyarn Node ID`
- `Storyarn Response ID`
- `Storyarn Flow Shortcut`
- `Storyarn Sheet Shortcut`

### Field Types

Use Dialogue System custom field types:

- Text: `type: 0`, `typeString: "CustomFieldType_Text"`
- Number: `type: 1`, `typeString: "CustomFieldType_Number"`
- Boolean: `type: 2`, `typeString: "CustomFieldType_Boolean"`
- Files: `type: 3`, `typeString: "CustomFieldType_Files"`
- Localization: use documented localization field pattern where needed.
- Actor reference: `type: 5`, `typeString: "CustomFieldType_Actor"`

Store values as strings unless the documented examples clearly use another
representation. Boolean field values should use `"True"` / `"False"` to match
Pixel Crushers examples.

## Storyarn Feature Mapping

### Sheets -> Actors

Each sheet becomes one actor.

Required fields:

- `Name`: sheet name
- `Display Name`: sheet name
- `Description`: optional / empty for now
- `IsPlayer`: default `False`

Custom fields:

- `Storyarn Sheet ID`
- `Storyarn Shortcut`

Open decision:

- Whether to infer player actor from a specific sheet flag/shortcut. For the
  first pass, create an explicit synthetic `Player` actor if responses need one.

### Variables

Project variables come from sheet blocks through `Helpers.collect_variables/1`.

Each variable becomes a Dialogue System variable asset.

Fields:

- `Name`: full Storyarn ref, e.g. `mc.jaime.health`
- `Initial Value`: default value
- `Description`: optional / empty
- `Storyarn Sheet Shortcut`
- `Storyarn Variable Name`

Lua expressions already use `Variable["full.ref"]`, so names should remain
dot-qualified.

### Flows -> Conversations

Each flow becomes one conversation.

Fields:

- `Title`: flow name
- `Description`: optional / empty
- `Actor`: default player actor id or `0`
- `Conversant`: first detected NPC/speaker actor or `0`
- `Storyarn Flow ID`
- `Storyarn Shortcut`

Conversation payload:

- `id`
- `fields`
- `overrideSettings`
- `dialogueEntries`
- `canvasScrollPosition`
- `canvasZoom`

### Entry Node

The Storyarn `entry` node becomes a root Dialogue System entry.

Expected:

- `isRoot: true`
- `isGroup: false`
- `Dialogue Text`: empty or `<START>`
- `outgoingLinks`: links to first reachable Storyarn nodes

### Dialogue Node

Storyarn dialogue maps to a Dialogue System dialogue entry.

Fields:

- `Actor`: speaker actor id when known
- `Conversant`: player actor id or fallback
- `Menu Text`: Storyarn `menu_text`
- `Dialogue Text`: stripped Storyarn text
- `Sequence`: generated from supported audio/sequence data, initially empty
- `Description`: stage directions or empty
- `Storyarn Node ID`
- `Storyarn Localization ID`
- `Storyarn Technical ID`

Runtime fields:

- `conditionsString`: node condition if present
- `userScript`: empty unless needed later
- `outgoingLinks`: to response entries or direct continuation

### Dialogue Responses

Responses should become PC dialogue entries because Dialogue System models
player menu selections as entries with `Menu Text` / `Dialogue Text`.

Fields:

- `Actor`: player actor id
- `Conversant`: originating dialogue actor id where known
- `Menu Text`: response `menu_text` or response `text`
- `Dialogue Text`: response `text`
- `Storyarn Response ID`

Runtime fields:

- `conditionsString`: response condition
- `userScript`: response instruction assignments
- `outgoingLinks`: target branch for the response pin

### Condition Node

For boolean mode:

- Create a synthetic group/pass-through entry if needed.
- Links for true/false branches should carry condition expressions where Unity
  can evaluate them, or route through synthetic entries with `conditionsString`.

For switch mode:

- Each branch should become a conditioned synthetic entry or link route.
- Use the same case extraction rules implemented in
  `GraphTraversal.condition_cases/2`.

Open decision:

- Dialogue System evaluates conditions on destination entries. Prefer synthetic
  entries per branch with `conditionsString` over trying to place conditions on
  links, because documented JSON exposes `conditionsString` on entries.

### Instruction Node

Create a synthetic entry with:

- empty text fields
- `userScript`: Lua from `ExpressionTranspiler.transpile_instruction/2`
- link to continuation

### Hub And Jump

`hub`:

- Create a synthetic group entry or pass-through entry.
- Preserve label/hub id as fields.

`jump`:

- Link directly to target hub entry where resolvable.
- If the target cannot be resolved, emit an entry with a clear custom field and
  no outgoing links rather than silently linking to an invalid id.

### Subflow

Storyarn subflow references another flow. Dialogue System can link across
conversations through `destinationConversationID`.

First pass:

- Link subflow entry to the root entry of the referenced conversation when the
  flow is included in the export.
- If the referenced flow is not included, emit a synthetic entry with metadata
  and no broken link.

Later:

- Model caller return / subflow exits more accurately if Dialogue System supports
  the desired call/return behavior without custom code.

### Exit

`terminal`:

- Create an end entry with no outgoing links.
- Include outcome label/tags/color as fields.

`flow_reference`:

- Link to referenced flow root if included.

`caller_return`:

- First pass: create terminal return marker entry with custom field
  `Storyarn Exit Mode = caller_return`.
- Later: map to a stronger Unity behavior only if we establish a supported
  Dialogue System pattern.

### Sequence Node

Storyarn sequence nodes are visual/staging containers, not dialogue nodes.

First pass:

- Do not export sequence nodes as dialogue entries.
- Preserve sequence membership as custom fields on child dialogue entries where
  possible:
  - `Storyarn Sequence ID`
  - `Storyarn Sequence Name`

Future pass:

- If `sequence_visual_layers` or `sequence_tracks` are needed, decide a Unity
  convention:
  - custom fields only
  - generated Dialogue System `Sequence` commands
  - external runtime integration

### Unity Sequence Field

Dialogue System's `Sequence` field controls per-entry cutscene commands.

Safe first mappings:

- No audio asset: empty `Sequence`.
- Dialogue `audio_asset_id` with resolvable stable asset name: consider
  `AudioWait(entrytag)` or `AudioWait(assetName)` only after confirming asset
  naming expectations in Storyarn export.

Do not emit commands for visual layers or audio tracks until the expected Unity
asset naming/runtime convention is defined.

### Localization

Dialogue System supports localized fields by suffixing language codes, e.g.
`Dialogue Text es`.

First pass:

- Keep base source fields.
- If `project_data.localization` is available, add localized `Dialogue Text xx`
  / `Menu Text xx` fields for matching Storyarn localization ids.

If lookup is too broad for the first implementation, add tests and leave the
implementation for a second commit.

## Implementation Phases

### Phase 1: Contract Skeleton

- Replace custom root envelope with DialogueDatabase root.
- Add field helpers and asset helpers.
- Build actors, variables, and conversations in the documented shape.
- Build root entries and simple dialogue entries.
- Generate correct `outgoingLinks` for linear flows.

Tests:

- root keys and absence of custom `database`
- actor field shape
- variable field shape
- conversation field shape
- linear entry outgoing links

### Phase 2: Branching

- Add response entries.
- Link dialogue -> response -> response target.
- Add response conditions and user scripts.
- Add boolean condition node support.
- Add switch condition support.

Tests:

- two responses produce two player entries
- response branches link to their targets
- response conditions become `conditionsString`
- response assignments become `userScript`
- boolean condition routes true/false
- switch condition routes labeled branches

### Phase 3: Flow Control Nodes

- Add hub/jump support.
- Add exit support.
- Add subflow cross-conversation links.

Tests:

- jump links to hub entry
- terminal exit has no outgoing links
- flow_reference exit links to referenced flow root
- subflow links to referenced conversation root when exported

### Phase 4: Metadata And Sequence Fields

- Add Storyarn custom fields consistently.
- Preserve canvas position in `canvasRect`.
- Preserve stage directions in `Description` or custom field.
- Add minimal `Sequence` generation only for confirmed safe audio mapping.

Tests:

- Storyarn ids are retained as custom fields
- `canvasRect` reflects node position
- stage directions are exported outside `Dialogue Text`

### Phase 5: Localization

- Add localized dialogue/menu/display fields.

Tests:

- source text remains in base `Dialogue Text`
- localized text appears in `Dialogue Text <locale>`
- non-matching locale data does not create bogus fields

## Test Strategy

Update `test/storyarn/exports/serializers/unity_json_test.exs`.

Remove assertions that validate the current placeholder structure:

- `format == "unity_dialogue_system"`
- `database`
- `entries`
- `links_to`
- `dialogue_text`
- `conditions`
- `user_script`

Replace them with contract assertions:

- `actors`, `variables`, `conversations` are root-level arrays.
- Field lists contain `title`, `value`, `type`, `typeString`.
- Conversations contain `dialogueEntries`.
- Entries contain `conversationID`, `isRoot`, `isGroup`,
  `outgoingLinks`, `conditionsString`, `userScript`, `canvasRect`.
- Links reference valid conversation and dialogue entry ids.

Add helper assertions in the test file:

- `field_value(asset_or_entry, title)`
- `field(asset_or_entry, title)`
- `entry_by_storyarn_node_id(entries, node_id)`
- `entry_by_storyarn_response_id(entries, response_id)`
- `assert_link(from, to)`

## Validation Commands

Focused:

```bash
mix test test/storyarn/exports/serializers/unity_json_test.exs
```

Related export safety:

```bash
mix test test/storyarn/exports/serializers test/storyarn/exports/expression_transpiler
```

Final when the implementation is complete:

```bash
mix precommit
```

## Risks

- Dialogue System import may be stricter than the documented JSON examples.
- Subflow call/return may not have a native JSON-only representation.
- Storyarn sequence visual/audio layer data may need a Unity runtime package,
  not just JSON fields.
- Existing tests may currently encode incorrect behavior and need replacement,
  not minor edits.

## Suggested First Commit

Implement Phase 1 only:

- real root JSON shape
- field helpers
- actor/variable/conversation assets
- root/dialogue entries
- linear outgoing links
- focused tests

Do not include branching, subflows, localization, or sequence generation in the
first implementation commit. Those should be follow-up commits with targeted
tests.
