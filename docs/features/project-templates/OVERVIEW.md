# Project Templates & Feature Gating — Vision

**Status:** vision doc, 2026-04-20. Deferred but strategically important. Not committed to a timeline.

## Why this exists

Storyarn serves multiple personas with the same product — linear novelists, screenwriters, visual-novel authors, CRPG designers. Showing every feature to every user creates two failures:

1. **Simple author overwhelm:** a novelist opening Storyarn for the first time sees Scenes, Tables, Condition/Instruction nodes, Flags/Events, Formula engine — and bounces. The surface area terrifies them.
2. **Advanced author underwhelm:** the CRPG designer opening the same product wants all of it and can't tolerate a simplified stripped-down version.

The fix is not "build two products." It's **project templates** that pre-configure the UI per intent, with a universal escape hatch so no feature is ever permanently locked away from a paying user.

## Design principle: templates as starter-opinion, not permanent-hiding

Two approaches that look similar but feel opposite:

| Approach                                                                                         | How it feels                  | Risk                     |
| ------------------------------------------------------------------------------------------------ | ----------------------------- | ------------------------ |
| **Hide = remove** ("You chose Novel, Scenes does not exist for you")                             | Paternalistic, limiting       | High — "I paid for this" |
| **Hide = prioritize** ("You chose Novel, Scenes is available in Settings but not in the navbar") | Curated, respectful of agency | Low                      |

Storyarn must take the second. The escape hatch is mandatory.

**Analogy:** Notion's experience. A solo user never sees "Teamspaces admin panel" by default, but enabling it takes two clicks. Nobody complains that Notion "hides" features.

## Industry scan — what works, what doesn't

| Tool                                      | Mechanism                                              | Result                                              |
| ----------------------------------------- | ------------------------------------------------------ | --------------------------------------------------- |
| **Notion**                                | Templates preconfigure, `/` command reaches everything | ✅ Serves solo + enterprise with one product        |
| **Figma**                                 | Nothing hidden; UI is contextual                       | ✅ Power users feel no friction                     |
| **VS Code**                               | Profiles + workspace-specific extensions               | ✅ Activation by context                            |
| **Adobe Premiere "Workspaces"**           | Reorders panels, hides nothing                         | ✅ Transparency — everyone knows all features exist |
| **Canon cameras "Basic / Advanced menu"** | User-picked mode, easy switch                          | ✅ Respects user intelligence                       |
| **Unity templates (2D/3D/URP)**           | Change initial settings, UI stays                      | ✅ Neutral                                          |
| **Office Simplified Ribbon**              | Hides advanced commands                                | 🟡 Lukewarm — nobody loves it                       |
| **Wordpress Gutenberg FSE**               | Rigid templates hide controls                          | ❌ Constant friction                                |

**Pattern:** winners combine **templates that preconfigure** with a **visible escape hatch**. Losers hide features without a door back.

## Proposed shape for Storyarn

**At project creation:** 5 templates + a 2-3 item follow-up survey.

| Template         | Primary persona                              |
| ---------------- | -------------------------------------------- |
| **Novel**        | Linear or lightly branched prose             |
| **Screenplay**   | Film/TV script format                        |
| **Visual Novel** | Dialogue-heavy with branching, minimal state |
| **CRPG**         | Stats, conditions, reactive world            |
| **Custom**       | User picks every feature toggle manually     |

**Each template maps to a feature map:**

| Feature                       | Novel | Screenplay | Visual Novel | CRPG | Custom |
| ----------------------------- | ----- | ---------- | ------------ | ---- | ------ |
| Sheets                        | ✅    | ✅         | ✅           | ✅   | toggle |
| Flows                         | ✅    | ✅         | ✅           | ✅   | toggle |
| Scenes                        | —     | —          | —            | ✅   | toggle |
| Screenplays                   | ✅    | ✅         | —            | 🟡   | toggle |
| Condition / Instruction nodes | —     | —          | ✅           | ✅   | toggle |
| Table blocks                  | —     | —          | 🟡           | ✅   | toggle |
| Reactive formulas on blocks   | —     | —          | 🟡           | ✅   | toggle |
| Flags / Events                | —     | —          | 🟡           | ✅   | toggle |
| Premiere-style cue timeline   | —     | —          | 🟡           | ✅   | toggle |

**The escape hatch:** Project Settings → Features shows every feature with a current state + why it's hidden + an Enable button:

```
☑ Sheets                [enabled by template: Novel]
☑ Flows                 [enabled by template: Novel]
☐ Scenes                [hidden by template: Novel]   [Enable]
☐ Conditions            [hidden by template: Novel]   [Enable]
☐ Flags / Events        [hidden by template: Novel]   [Enable]
```

No feature is destroyed. Enabling is a single click. The template is a default, not a contract.

## How this unblocks other features

This system is the **pre-requisite for shipping complexity without scaring users.** Without it, every new power feature is an argument with the Novel segment. With it, each feature hides behind the template it belongs to.

Concretely, these in-development features depend on project templates:

- **Flags / Events** (`events-flags-system/OVERVIEW.md`) — only exposed in Visual Novel / CRPG / Custom templates with the feature enabled.
- **Reactive formulas on block values** (`tables-rule-engine/OVERVIEW.md` Tier 2) — CRPG-and-above.
- **Premiere timeline for flow direction** — CRPG-and-above.

Shipping these to all users would overwhelm. Hiding them without a door is paternalistic. Templates + escape hatch is the middle path that actually works.

## Discovery nudges (optional, later phase)

Contextual hints based on project usage:

- "Your project has 50 flows — try Tables to organize reusable data. [Enable]"
- "This is your 3rd time using variable flags — have you tried Events for cleaner cross-flow reactivity? [Enable]"

Dismissible. Educational, not coercive. Not needed in v1 — only worth building once the template system is proven.

## Monetization concern addressed

User raised the concern:

> **"This feature is huge and I'm not sure about the value it adds. This is a feature that removes content from the app — features the user has also paid for."** (translated from Spanish)

**Counter-argument:** what the user pays for is a fitting experience, not maximum feature surface area. Nobody paying for Microsoft Office feels cheated because they don't use Visual Basic. Nobody paying for Photoshop feels cheated because they never opened the video timeline.

The risk would exist only if features were **permanently locked** or **hidden without discoverability**. Neither applies here:

1. The Settings → Features list is always accessible and itemizes everything.
2. The escape hatch is a single click per feature.
3. Template copy explicitly states "Novel mode hides advanced features — enable them any time in Settings."

Hiding features **is value**, not subtraction. The user is paying for clarity of purpose, not for visual noise.

## Phased rollout

| Phase       | Scope                                                                                                          | Size    |
| ----------- | -------------------------------------------------------------------------------------------------------------- | ------- |
| **Phase 1** | Hardcoded feature flags + 3 templates (Novel, Visual Novel, CRPG). Settings → Features toggle list. No nudges. | ~1 week |
| **Phase 2** | Add Screenplay + Custom templates. Basic contextual discovery nudges.                                          | ~1 week |
| **Phase 3** | User-defined templates (save current feature config as project template).                                      | Later   |
| **Phase 4** | Analytics-driven default refinement: which features get enabled, by which templates, inform the default maps.  | Later   |

## Non-goals

- Don't build a plan-tier system around this. Free vs paid is a separate concern — features shouldn't gate behind payment via this system; gate behind **intent**.
- Don't ship user-defined templates (Phase 3) in v1. Hardcoded templates are enough to prove the concept.
- Don't gate with a modal that blocks the project until the user picks — make it a quick-create flow with a sensible default (e.g. Custom with all features on) for users who skip.
- Don't remove entity types from the database based on template. Only hide from UI. A "Novel" project technically has scenes_count=0; if the user enables scenes, the feature simply becomes visible.

## Related docs

- `docs/features/flow-player-redesign/OVERVIEW.md` — needs Project Templates to gate its richer future layers.
- `docs/features/events-flags-system/OVERVIEW.md` — cannot ship before this system because complexity needs a gate.
- `docs/features/tables-rule-engine/OVERVIEW.md` — Tier 2+ features gate behind CRPG template.
