# Space Journey Yarn fixture

This fixture is derived from **Space Journey**, an official playable Yarn
Spinner demo used by the Yarn Spinner 2 tutorial and GDC 2021 presentation. It
is intentionally realistic rather than Storyarn-authored: five narrative
documents branch from `Start` into three routes and reconverge at
`BridgeEnding`.

## Provenance and licence

- Repository: <https://github.com/YarnSpinnerTool/ExampleProjects>
- Pinned revision: [`954b71207fbe6992fe188d1ab22f8b6330080a2b`](https://github.com/YarnSpinnerTool/ExampleProjects/commit/954b71207fbe6992fe188d1ab22f8b6330080a2b)
- Source path: [`SpaceJourney/Assets/Dialogue/SpaceJourney_FinalVersion.yarn`](https://github.com/YarnSpinnerTool/ExampleProjects/blob/954b71207fbe6992fe188d1ab22f8b6330080a2b/SpaceJourney/Assets/Dialogue/SpaceJourney_FinalVersion.yarn)
- Upstream Git blob: `83f61dba31c9fbb24a62a270cbcc97ff3823a022`
- Licence: [MIT](https://github.com/YarnSpinnerTool/ExampleProjects/blob/954b71207fbe6992fe188d1ab22f8b6330080a2b/LICENSE.md), copyright 2021 Secret Lab Pty. Ltd.; the required notice is copied in `LICENSE.md`.
- Upstream description and credits: [`README.md`](https://github.com/YarnSpinnerTool/ExampleProjects/blob/954b71207fbe6992fe188d1ab22f8b6330080a2b/README.md)

GitHub reports that the repository was archived in 2025. The pinned revision
contains the MIT grant reproduced in `LICENSE.md`.

`upstream/SpaceJourney_FinalVersion.yarn` preserves the upstream source text.
Only transport details are normalized: its UTF-8 BOM is removed and a final LF
is present. The semantic test verifies that no other source text changed.

## Importable adaptation

The upstream demo was authored for Yarn Spinner 2, but its implicit variables
and `+=` assignment syntax are outside Storyarn's current fail-closed import
subset. `SpaceJourney_FinalVersion.yarn` is a deterministic,
semantics-preserving adaptation:

1. It declares `$away_mission_readiness` as `0` and `$captain_is_friend` as
   `false` at the beginning of `Start`.
2. It rewrites the three `+= 1` assignments to the equivalent
   `to $away_mission_readiness + 1` form.
3. `SpaceJourney.yarnproject` is a Storyarn-added v3 descriptor that selects
   only the adapted source. The upstream demo did not ship this descriptor.

No narrative line, choice, node title, jump, condition, speaker spelling, or
engine command was edited. In particular, the upstream `Crewemate` typo stays
literal and is deliberately preserved during the tested review decision.

`compatibility-manifest.json` records the exact accepted, transformed,
preserved-for-review, omitted, and rejected constructs. Tests package only the
project descriptor and adapted source as a ZIP; the upstream copy and licence
are provenance evidence, not import inputs.
