%{
title: "Snapshots and Trash",
category_label: "Project Management",
order: 5,
description: "Create project backups, restore a known state, and recover or permanently delete content."
}

---

Storyarn has two complementary recovery tools:

- **Snapshots** preserve a point-in-time state of the project.
- **Trash** holds supported entities that were soft-deleted from the project.

Use a snapshot before a broad migration or structural change. Use Trash when you only need to recover an individual deleted item.

## Project snapshots

Open **Project Settings > Snapshots**. Enter an optional title and description, then choose **Create Snapshot**. Creation is subject to the current plan limit shown under Version Control and Usage Limits.

Each stored snapshot shows its version number, title, creator when available, creation time, stored size, and entity counts. Available actions are:

- **Download** the stored snapshot archive.
- **Restore** the project to that snapshot.
- **Delete** the snapshot permanently.

Restoration is a project-wide operation and runs under a restoration lock. Other restoration actions are disabled while it is in progress. Only clear a stale lock when you have confirmed that no restoration job is still running.

Restoring can replace current project data with the snapshot state. Create a fresh snapshot first when you may need to return to the current state.

## Automatic snapshots and entity versions

In **Project Settings > Version Control**, you can enable daily project snapshots separately from automatic Sheet, Flow, and Scene versions.

Entity versions are useful for reviewing or restoring one content item. Project snapshots are broader recovery points. Their usage limits are tracked separately.

## Trash

Open **Project Settings > Trash** to inspect soft-deleted Sheets, Flows, Scenes, and other supported content types. You can:

- Search by name.
- Filter by item type.
- Move through paginated results.
- Restore an item.
- Permanently delete one item.
- Empty the entire trash.

Restore returns the item to active project content. Permanent deletion and **Empty Trash** cannot be undone through the Trash interface. These destructive actions are only available to users with management permission.

## Recommended recovery sequence

1. Check Trash when a single item is missing.
2. Inspect entity version history when the item exists but its content is wrong.
3. Use a project snapshot when several related entities must return to a consistent earlier state.
4. Download important snapshots before deleting them or performing a high-risk migration.
