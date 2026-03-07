%{
  title: "Real-time Collaboration",
  category_label: "Collaboration",
  order: 1,
  description: "Work together with your team in real time -- presence, cursors, and locking."
}
---

Storyarn is built for teams. The {accent}Flow Editor{/accent} supports full real-time collaboration -- you can see who is online, follow their cursors across the canvas, and edit nodes without conflicts thanks to automatic locking.

Collaboration features are currently available in the Flow Editor, where the interactive canvas and node-based editing benefit most from real-time coordination. Other editors (sheets, scenes, screenplays) use standard optimistic saving.

## Presence

When you open a flow, every teammate working in the same flow sees your avatar appear in the online users list. Each user is assigned a {accent}deterministic color{/accent} from a 12-color palette designed for visibility on both light and dark themes. Your color stays consistent across sessions -- it is derived from your user ID, so teammates always recognize you by the same color.

The presence system is powered by Phoenix Presence, which means it handles disconnections gracefully. If you close the tab or lose your connection, your avatar disappears automatically.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The flow editor header showing online user avatars, each with their assigned collaboration color
</div>

## Cursor tracking

As you move your mouse across the flow canvas, your teammates see a {accent}live cursor{/accent} labeled with your email and drawn in your assigned color. Cursor positions are broadcast in real time via PubSub, so the movement feels instantaneous.

When you leave the flow (navigate away or close the tab), your cursor disappears from everyone else's canvas immediately.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  The flow canvas with two remote cursors visible, each labeled with the user's name and shown in their collaboration color
</div>

## Node locking

To prevent conflicting edits, Storyarn uses {accent}automatic node locking{/accent}. When you select a node, a lock is acquired for you behind the scenes. Other team members see a lock indicator on that node showing your email and color -- they can view the node but cannot edit it while your lock is active.

Key details about locking:

- **Automatic acquisition** -- Locks are acquired the moment you select a node. No manual action needed.
- **30-second timeout** -- Locks expire after 30 seconds of inactivity. A heartbeat mechanism refreshes the lock while you are actively working.
- **Automatic release** -- Locks are released when you deselect the node, navigate to a different flow, or disconnect.
- **Conflict handling** -- If you try to select a node that someone else has locked, you will see who holds the lock so you can coordinate.
- **Expired lock cleanup** -- A background process runs every 10 seconds to clean up any expired locks, ensuring stale locks never block your team.

Only the lock holder can release their own lock. This prevents race conditions where two users might try to edit the same node simultaneously.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  A flow node with a lock indicator showing another user's name and color, indicating it is currently being edited
</div>

## Remote changes and toasts

When a teammate makes a change -- creating, updating, or deleting a node -- the flow canvas {accent}updates automatically{/accent} for everyone. The flow data is reloaded and the canvas re-renders so you always see the latest state.

Collaboration toasts appear briefly to let you know what happened:

- Lock acquired or released on a node
- Node created, updated, moved, or deleted
- Connection added or removed

Toasts show the user's email and are color-coded with their collaboration color. They dismiss automatically after a few seconds.

## The color palette

Storyarn assigns each user one of 12 colors based on their user ID. The palette uses Tailwind's 500-weight colors for strong visibility:

red, orange, amber, lime, green, teal, cyan, blue, indigo, violet, fuchsia, pink

A lighter variant of each color (300-weight) is also available for subtle elements like cursor trails.

## Roles and permissions

Collaboration respects the project role hierarchy. All roles can see presence, cursors, and toasts. Only users with edit permissions (Owner, Editor) can acquire locks and make changes. Viewers see everything in real time but cannot modify anything -- lock acquisition is denied server-side, not just hidden in the UI.

| Role | Sees presence | Sees cursors | Can edit nodes |
|------|:---:|:---:|:---:|
| **Owner** | Yes | Yes | Yes |
| **Editor** | Yes | Yes | Yes |
| **Viewer** | Yes | Yes | No |
