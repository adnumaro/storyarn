# Epic 5 — Visual Diffs

> Diff highlighting on the canvas — nodes, connections, and elements colored by change type in split view

## Context

After Epic 4 (Version Intelligence), users can compare two versions side-by-side using the split view. However, they must manually spot differences by scanning both editors. For simple changes this works, but for large flows with many nodes or scenes with many pins, finding what changed is tedious.

Visual diffs solve this by highlighting changes directly on the canvas: added elements in green, removed in red, modified in amber. Combined with the split view from Epic 4, this creates a complete visual comparison experience.

**Depends on:** Epic 4 (specifically Feature 1: Diff Engine + Feature 4: Split View)

---

## Feature 1: Diff Highlighting in Split View

### What
When comparing two versions in split view, color-code elements (nodes, connections, pins, zones, blocks) by their change status: added, removed, or modified.

### Design

**Data flow:**
1. Parent editor computes diff via `SnapshotDiff.diff/3` between current state and the compared version
2. Diff result is sent to both the main editor and the iframe via `postMessage`
3. Each editor applies CSS classes to highlight elements by their change status

**Visual language:**
- **Added** — green border/background tint
- **Removed** — red border/background tint (shown only in the historical version)
- **Modified** — amber border/background tint
- **Unchanged** — dimmed/faded to reduce noise

---

## Feature 2: Synchronized Navigation

### What
Sync zoom and pan between the two split view panes so both editors show the same area of the canvas.

---

## Feature 3: Change Navigation

### What
"Next change" / "Previous change" buttons that jump between modified elements across the canvas, centering both views on the relevant area.

---

## Scope

This epic will be designed in detail when Epics 1–4 are complete. The architecture in earlier epics (snapshot format, diff engine, split view with iframe + `postMessage` bridge) is designed with visual diffs in mind.
