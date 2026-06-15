%{
title: "Annotation Nodes",
category_label: "Narrative Design",
section_label: "Node Types",
section_order: 1,
order: 8,
description: "Add visual notes to a flow without changing execution."
}

---

Annotation nodes are canvas notes. They help teams explain intent, mark open questions, leave TODOs, or group context around nearby flow nodes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Flow canvas with annotation notes beside a branching dialogue section
</div>

## Execution behavior

Annotations do not execute. They do not affect dialogue playback, debugging, variables, localization extraction, or exports.

## Good uses

- Mark design intent: "This branch is for low-trust players."
- Leave implementation notes for teammates.
- Identify sections that need writing, localization review, or QA.
- Explain why a condition exists.
- Add temporary TODOs while shaping a large graph.

## Keep annotations useful

Use annotations to clarify the graph, not to duplicate everything already visible in the nodes. If an annotation becomes permanent documentation for a reusable system, consider moving that explanation into project docs or naming the surrounding nodes more clearly.
