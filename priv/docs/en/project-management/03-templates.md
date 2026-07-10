%{
title: "Project Templates",
category_label: "Project Management",
order: 3,
description: "Publish reusable project templates, version them, and create projects from private templates or Storyarn demos."
}

---

Project templates let you reuse a project structure without rebuilding its sheets, flows, scenes, and supporting data from scratch. Storyarn distinguishes your private templates from public Storyarn demos.

## Publishing a template

Open the source project and go to **Project Settings > General > Templates**. Choose **Publish template**, then select one of two modes:

- **New template** creates a new private template from the current project.
- **Update template** publishes a new immutable version of one of your existing private templates.

Enter a template name, description, and optional version notes. Publication runs in the background and reports whether it is queued, running, retrying, published, or failed. Only one active publication for the same source or template can run at a time, and plan limits can restrict the number of templates or versions.

## Browsing templates

Open **Templates** from the workspace-level navigation. The library separates:

- **Private templates** you can access.
- **Storyarn demos** published for all users.
- **Archived templates** that you manage.

Search by name or description. A template page shows its current version, entity counts, preview data, version notes, publication history when available, and previous versions.

## Creating a project from a template

You can install a template from its detail page by choosing an eligible workspace and entering the new project's name and description.

You can also open **New Project** from a workspace dashboard and switch from **Blank** to **My templates** or **Storyarn demos**. Select a template, review its content counts, and create the project. The new project is independent: later template versions do not overwrite it automatically.

## Managing private templates

Template owners can publish a new version, edit supported metadata, and archive a template. Archived templates are removed from normal selection but remain recoverable. Permanent deletion is only available after a template has been archived.
