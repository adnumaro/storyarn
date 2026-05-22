%{
title: "Sequence Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 7,
description: "Group related nodes and build visual stage compositions for Flow Player playback."
}

---

Sequence nodes are visual containers for related parts of a flow. Use them to group a scene beat, conversation section, combat setup, tutorial step, or any cluster of nodes that should read as one unit.

Sequences also define presentation context for Flow Player. When playback reaches a node inside a sequence, the player can show that sequence's visual layers behind the dialogue panel and play its sequence-level audio tracks.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Flow canvas with a Sequence node containing dialogue, condition, and instruction nodes
</div>

## What a sequence contains

A sequence can contain other flow nodes. The contained nodes keep their normal behavior; the sequence gives them a shared visual boundary and configuration surface.

Use sequences to:

- Keep large graphs readable.
- Name a narrative beat.
- Move a group of nodes together.
- Add visual layers around a beat.
- Attach audio tracks to a grouped section.

## Flow Player presentation

In Flow Player, sequences work like a lightweight stage composition. The active node determines its sequence chain. Storyarn collects the visual layers and audio tracks from each parent sequence, then from each child sequence, and renders them together during playback.

This lets you build visual sequences without leaving the flow:

| Layer kind | Typical use |
| ---------- | ----------- |
| **Backdrop** | Main background image for the beat, such as an interior, battlefield, memory, or cutscene frame. |
| **Character** | Character art positioned over the backdrop, usually left, center, or right. |
| **Prop** | Objects, clues, UI-like inserts, or scene details that should appear during the sequence. |
| **Overlay** | Full-frame effects, lighting, weather, vignettes, or foreground treatments. |

The dialogue UI remains above the stage composition. Visual layers are normalized to the player viewport, so the same setup scales across screen sizes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Flow Player showing a sequence backdrop with character layers over it and the dialogue panel in front
</div>

## Parent and child sequences

Nested sequences compose from outside to inside. Parent sequence layers render first, then child sequence layers render above them.

Use this when a larger section has a shared base presentation, but a smaller beat needs extra staging:

```text
Tavern conversation sequence
  Backdrop: tavern interior
  Music: tavern theme

  Secret reveal child sequence
    Overlay: darker lighting
    Character: suspicious NPC close-up
    SFX: door lock
```

When playback enters the child sequence, the player keeps the parent context and adds the child-specific layers and tracks.

## Wrapping nodes

Select one or more nodes and wrap them into a sequence when they form a coherent beat. The selected nodes become children of the new sequence.

Avoid wrapping unrelated parts of the graph just because they are near each other spatially. A good sequence has a meaningful name.

## Size and nesting

Sequence bounds adapt around their children, and manual resizing is constrained so the container cannot become smaller than the nodes inside it. Nested sequences are supported, but use them sparingly: too many nested containers can make a graph harder to scan.

## Visual layers and tracks

Sequences can own visual layers and audio tracks. Select a sequence and open its configuration panel to add image layers or audio assets.

Visual layers support kind, slot, fit mode, opacity, and normalized frame placement. Character layers have useful default slots such as left, center, and right; backdrop and overlay layers default to full-frame cover.

Audio tracks are sequence-level loops for **music**, **ambience**, and **sfx**. Use them to establish the mood of a beat while it plays. The browser may wait for a user gesture before autoplaying audio, depending on browser policy.

Use visual layers and tracks when a grouped beat needs richer presentation or timing context beyond simple graph organization.
