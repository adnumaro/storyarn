%{
title: "Legacy Sequence Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 7,
description: "Compatibility with existing Sequence containers and the current visual editor."
}

---

New visual compositions belong to dialogue nodes and are edited in the [Sequence editor](/docs/narrative-design/sequence-editor). You do not need a Sequence node to add backgrounds, characters, props, overlays or audio.

Sequence containers can still appear in existing projects. Storyarn preserves their contents and composition data for compatibility. A dialogue can explicitly continue a composition from another dialogue or an existing Sequence container; moving nodes inside a container does not create visual inheritance.

For new work, open the visual editor with **Play**, select a dialogue, and choose **Continues from** when it should share an existing composition. Use **Condition** nodes and separate dialogues when a branch needs different staging or voice.
