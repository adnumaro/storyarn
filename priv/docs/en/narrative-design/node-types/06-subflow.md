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

<img src="/images/docs/flows-editor-current.png" alt="Parent flow with a Subflow node whose output pins come from the referenced flow's Exit nodes" loading="lazy">

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
