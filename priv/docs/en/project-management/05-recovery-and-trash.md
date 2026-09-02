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

- **Cancel build** while a snapshot is pending, building, or being verified, until finalization begins.
- **Restore** a ready, verified snapshot that meets the current restore contract. This durable background operation replaces the active project graph and assets. Current Sheets, Flows, Scenes, and assets move to recoverable trash; the project and its memberships remain intact.
- **Download** a ready, verified snapshot as a private ZIP archive. Storyarn checks your permission for every request, then the browser downloads the persisted archive directly from private storage.
- **Delete** the snapshot permanently.

Only snapshots that satisfy the verified restore requirements show the restore action. A restore continues safely if you leave the page, and the Snapshots page shows its progress and result.

## Manual snapshots and automatic entity versions

Project snapshots are created manually from **Project Settings > Snapshots**. Storyarn does not currently offer a daily project snapshot switch or production flow.

In **Project Settings > Version Control**, you can enable automatic versions independently for Sheets, Flows, and Scenes. Entity versions are useful for reviewing or restoring one content item. Project snapshots cover the whole project and are also downloadable backups. Their usage limits are tracked separately.

## Recover a project from a downloaded ZIP

A downloaded Storyarn snapshot ZIP can rebuild the captured project as a new project in a workspace. Open **Workspace Settings > Imports** for the destination workspace, choose the ZIP, then select **Validate and import**.

Storyarn validates the archive and checks the workspace's project and storage capacity before starting the background import. The Imports page shows progress and import history, and lets you open the rebuilt project after completion. You need permission to manage the selected workspace.

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
3. Restore a verified snapshot in place when you need to return the current project to an earlier complete state.
4. Import a downloaded snapshot ZIP from Workspace Settings when you need to rebuild the captured project as a new project.
5. Download important snapshots before deleting them or performing a high-risk migration.
