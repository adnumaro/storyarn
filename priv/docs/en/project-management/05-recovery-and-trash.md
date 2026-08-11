%{
title: "Snapshots and Trash",
category_label: "Project Management",
order: 5,
description: "Create project backups and recover or permanently delete supported content."
}

---

Storyarn has two complementary recovery tools:

- **Snapshots** preserve a point-in-time state of the project.
- **Trash** holds supported entities that were soft-deleted from the project.

Use a snapshot before a broad migration or structural change. Use Trash when you only need to recover an individual deleted item.

## Project snapshots

Open **Project Settings > Snapshots**. Enter an optional title and description, then choose **Create Snapshot**. Creation is subject to the current plan limit shown under Version Control and Usage Limits.

Snapshot creation continues in the background. Storyarn builds one private ZIP archive and only marks the snapshot ready after the archive and its manifest have been verified. The stored size is the ZIP plus that small manifest; Storyarn does not keep a second snapshot copy of every file beside the ZIP.

Each stored snapshot shows its version number, title, creator when available, creation time, stored size, and entity counts. Available actions are:

- **Download** a ready, verified full snapshot as a private ZIP archive. Storyarn checks your permission for every request, then the browser downloads the persisted archive directly from private storage. Linked snapshots and older snapshots that have not been prepared as archives are not downloadable.
- **Delete** the snapshot permanently.

Project snapshot restoration is not currently available in the interface. Keep downloaded archives as project-wide backups; entity versions and Trash provide the in-product restore paths described below.

## Automatic snapshots and entity versions

In **Project Settings > Version Control**, you can enable daily project snapshots separately from automatic Sheet, Flow, and Scene versions.

Entity versions are useful for reviewing or restoring one content item. Project snapshots are broader downloadable backups. Their usage limits are tracked separately.

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
3. Use a downloaded project snapshot as a project-wide backup when several related entities are involved.
4. Download important snapshots before deleting them or performing a high-risk migration.
