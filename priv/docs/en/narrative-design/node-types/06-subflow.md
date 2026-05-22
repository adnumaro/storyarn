%{
title: "Subflow Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 6,
description: "Reuse a flow inside another flow and branch from its exit outcomes."
}

---

Subflow nodes let one flow call another. They are the main tool for composing larger narrative systems from smaller reusable pieces.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Parent flow with a Subflow node whose output pins come from the referenced flow's Exit nodes
</div>

## How subflows execute

When execution reaches a Subflow node:

1. Storyarn enters the referenced flow at its Entry node.
2. The referenced flow runs normally.
3. If it reaches an Exit node set to return to caller, execution returns to the parent flow.
4. The parent flow continues from the output pin that matches the exit outcome.

The Story Player and debugger support nested execution with a call stack, so you can inspect where the current run came from and where it will return.

## Output pins

Subflow output pins are generated from the referenced flow's return exits. This makes reusable flows explicit: the parent flow sees the outcomes it can react to.

For example, a `merchant_bargain` flow might expose:

```text
agreed
refused
not_enough_gold
relationship_too_low
```

## Circular references

Storyarn prevents circular flow references. A flow cannot call itself directly or indirectly through a chain of subflows.

## When to create a subflow

Use subflows for reusable conversations, shared checks, repeated quest beats, tutorials, or any narrative chunk that needs its own internal structure but should remain callable from more than one place.
