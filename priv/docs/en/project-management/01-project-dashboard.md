%{
title: "Project Dashboard",
category_label: "Project Management",
order: 1,
description: "Read project metrics, warnings, localization progress, and recent activity."
}

---

The project dashboard is the first page you see after creating or opening a project. It gives you a read-only overview of the project and links directly to the content that needs attention.

## Project totals

The cards at the top summarize:

- **Sheets** and exposed **Variables**.
- **Flows** and dialogue lines.
- **Scenes**.
- Total localizable word count: the same player-facing flow and sheet text included by the runtime export contract.

The Sheets, Variables, Flows, Dialogue, and Scenes cards open their corresponding workspaces. The localizable-word card is informational. It excludes scenes, screenplays, and editor-only labels or descriptions.

## Narrative breakdown

**Node Distribution** shows how many flow nodes exist for each node type and the percentage each type represents. Use it to spot projects dominated by one kind of node or to confirm that expected logic nodes have been created.

**Top Speakers** lists the sheets used most often as dialogue speakers. When a speaker can be resolved to a sheet, its name links to that sheet.

## Issues and warnings

The dashboard reports project-level issues discovered from current content: flows without an Entry node, disconnected or dead-end nodes, sheets without blocks, and incomplete translations for configured target languages. Each item links to the relevant tool so you can inspect the source.

The dashboard is a summary, not a replacement for [pre-export validation](/docs/import-export/import-export-overview#pre-export-validation). Run export validation before producing an engine file.

## Localization and activity

When target languages exist, **Localization Progress** shows final translations versus total strings for each language and links to the Localization workspace.

**Recent Activity** lists recently updated sheets, flows, scenes, and other supported content with relative timestamps. It helps a team see where work is currently concentrated.

## Next steps

- Open [Assets](/docs/project-management/assets) to manage project media.
- Review [Project Settings](/docs/project-management/project-settings) before inviting collaborators or configuring versioning.
- Use [Snapshots and Trash](/docs/project-management/recovery-and-trash) before a risky bulk change.
