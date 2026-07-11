%{
title: "Create a Workspace",
category_label: "Quick Start",
order: 1,
description: "Set up your workspace and create your first project in under 5 minutes."
}

---

A {accent}workspace{/accent} is your team's home base. It holds all your projects and controls who has access to them.

This Quick Start builds one small, complete project path:

1. Create a workspace and project.
2. Create a character sheet with variables.
3. Use those variables in a branching flow.
4. Test the flow with the Story Player and Debug Mode.
5. Export the project so it can move into your production pipeline.

## Create your workspace

After signing in, you will be redirected to your default workspace. If you don't have one yet, you will land on the **Create a new workspace** page.

Fill in the {accent}workspace name{/accent} and an optional description. A URL slug is generated automatically from the name. Click **Create Workspace** to proceed.

<img src="/images/docs/workspace-new.png" alt="The &quot;Create a new workspace&quot; form with name and description fields" loading="lazy">

## Create a project

From the workspace dashboard, click the **New Project** button in the top-right toolbar. The project dialog lets you start from a blank project, one of your templates, or a Storyarn demo, then enter a **Project Name** and optional **Description**.

Each project is fully isolated with its own sheets, flows, scenes, localization, and assets. One workspace can hold as many projects as you need.

<img src="/images/docs/workspace-dashboard-current.png" alt="The workspace dashboard showing the project grid and the &quot;New Project&quot; button in the toolbar" loading="lazy">

<img src="/images/docs/project-new.png" alt="The New Project dialog with Blank, My templates, and Storyarn demos choices" loading="lazy">

After creation, you are taken to the project dashboard. Open **Sheets** from the project sidebar to continue.

For this tutorial, stay in the new project and continue with [Your First Sheet](/docs/quick-start/first-sheet). You will create the character data that the flow reads in the next step.

## Invite your team

Go to **Settings > Workspaces > [Your Workspace] > Members** and click **Invite**. Enter an email address and choose a role:

- {accent}Owner{/accent} -- full control, including deletion
- {accent}Admin{/accent} -- manage members, create and delete projects
- {accent}Member{/accent} -- edit content in projects they have access to
- {accent}Viewer{/accent} -- read-only access everywhere

Invitations expire after 7 days and can be revoked anytime.

<img src="/images/docs/workspace-members.png" alt="The workspace members settings page with the invite form, member list, and pending invitations" loading="lazy">

## Project-level access

Within each project, you can further refine permissions. A workspace Member can be an Editor on one project but a Viewer on another. Project roles are:

- {accent}Owner{/accent} -- full project control
- {accent}Editor{/accent} -- create and edit all content
- {accent}Viewer{/accent} -- read-only access

Manage project members from the project's **Settings** page.
