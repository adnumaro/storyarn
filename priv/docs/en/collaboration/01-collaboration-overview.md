%{
  title: "Real-time Collaboration",
  category_label: "Collaboration",
  order: 1,
  description: "Work together with your team in real time — presence, cursors, and locking."
}
---

Storyarn is built for teams. Multiple people can work on the same project simultaneously with real-time presence, cursor tracking, and conflict-free editing.

## Presence

When you open a project, your teammates see you're online:

- **Avatar indicators** show who's currently in the project
- Each user gets a **unique color** for easy identification
- You can see which specific entity someone is editing

## Cursor tracking

On canvas views (flows and scenes), you can see **live cursors** from other team members — each labeled with their name and shown in their assigned color.

## Entity locking

To prevent conflicting edits, Storyarn uses **optimistic locking**:

- When you select a node, sheet, or other entity to edit, it's **locked** for you
- Other team members see a lock indicator and can view but not edit
- Locks release automatically when you navigate away or disconnect
- If someone has a lock on what you need, you'll see who — coordinate with them

## Collaboration toasts

Real-time notifications appear when team members take actions:

- *"Elena is editing the Tavern Encounter flow"*
- *"Kai added a new character sheet"*
- *"Elena unlocked the Quest Log node"*

## Roles and permissions

Collaboration respects the role hierarchy:

| Role | Can edit | Can view | Sees presence |
|------|---------|---------|--------------|
| **Owner/Admin** | Yes | Yes | Yes |
| **Editor** | Yes | Yes | Yes |
| **Viewer** | No | Yes | Yes |

Viewers see everything in real time but cannot make changes.
