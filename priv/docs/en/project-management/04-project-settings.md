%{
title: "Project Settings",
category_label: "Project Management",
order: 4,
description: "Configure project details, access, localization, versioning, limits, and maintenance."
}

---

Open **Settings** from the project sidebar to configure project-wide behavior. The available actions depend on your project role.

## General

The General page includes:

- Project name, description, type, and subtype.
- Template publication for creating or updating a private template.
- The source language currently used by Localization.
- Personal light, dark, or system appearance selection.
- Project primary and accent colors, with an option to restore the defaults.
- A maintenance action that repairs variable references.
- Project deletion in the danger zone.

Deleting a project removes it from the active workspace and returns you to the workspace dashboard. Treat this as an administrative action and verify recovery requirements first.

## Version Control

Version Control has separate switches for:

- Daily project snapshots.
- Automatic versions for Flows.
- Automatic versions for Scenes.
- Automatic versions for Sheets.

The page also shows current usage against the plan allowance for project snapshots and named entity versions. Save after changing the switches.

## Usage Limits

Usage Limits is read-only. It shows the active plan and current usage for project items, project snapshots, named versions, workspace storage, projects, and members. Item totals are broken down into sheets, flows, scenes, and flow nodes. A status badge warns when a limit is close or has been reached.

## Localization provider

Use **Localization** settings to enter a DeepL API key, choose the Free or Pro endpoint, test the connection, and inspect reported character usage. See [Localization Overview](/docs/localization/localization-overview) for the translation workflow.

## Members

The project member list shows each member and their current role. Project invitations can grant **Editor** or **Viewer** access. Owners cannot be removed from this list, and the current user cannot remove themselves with the member-removal action.

Workspace membership and project membership are separate. A person must be able to access the workspace before project-level access is useful. See [Create a Workspace](/docs/quick-start/create-workspace#project-level-access).

## Export

The Export page configures engine format, included sections, asset handling, formatting, and pre-export validation. See the dedicated [Export guide](/docs/import-export/import-export-overview).

Snapshots and Trash are covered separately in [Snapshots and Trash](/docs/project-management/recovery-and-trash).
