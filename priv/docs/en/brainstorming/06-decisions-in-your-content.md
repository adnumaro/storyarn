%{
title: "Decisions in Your Content",
category_label: "Brainstorming",
order: 6,
description: "Start explorations from a Sheet, Flow, or Scene, and find, apply, and follow up the decisions that affect it."
}

---

Brainstorming connects to the rest of your project in both directions. You can start a session from the content you want to change, and the decisions that affect a Sheet, Flow, or Scene appear in its editor, in your inbox, on the dashboard, and in the command palette until they are applied.

## Explore changes from your content

Every Sheet, Flow, and Scene editor has an **Explorations** button, a lightbulb in its header. It opens a dialog with three parts:

- **Starting context**: an overview of the content, such as its name, shortcut, and description. It is saved with the session as a reference; it is not an editable copy and it does not change the original.
- **Decisions about** the content, when there are any. See [below](#decisions-in-the-editor).
- **Linked explorations**: the sessions that already explore this content. Select **Resume** to continue one.

<img src="/images/docs/brainstorming/brainstorming-explorations.webp" alt="The Explorations dialog opened from the Flow Act 3 endings, with its starting context, the decisions about it, and a linked exploration to resume" loading="lazy">

To start a new session about the content, select **New exploration**, give it a title and optionally write what you would like to explore, then select **Create and explore**. To add the content to a session that already exists, select **Link existing** and search for it by title.

<img src="/images/docs/brainstorming/brainstorming-explore-new.webp" alt="The New exploration form in the Explorations dialog of the Sheet Mara, with a title and the question to explore" loading="lazy">

Viewers can open and resume the explorations they have access to, but need editing access to create or link one.

## References inside a session

A session can keep more of the project at hand than its starting content. **Session references**, the link icon at the top left of the canvas, lets you link Sheets, Flows, Scenes, Assets, and localized texts to the session, each with a purpose such as **Reference** or **Affects**.

<img src="/images/docs/brainstorming/brainstorming-references.webp" alt="The Session references panel with content type and purpose selectors and a linked Scene, The lighthouse, whose overview is unchanged" loading="lazy">

Each reference keeps the overview you consulted when you linked it. If the content changes later, the reference says **Overview changed since linking**, and **Open current content** takes you to the editor. Linking never changes the original content.

## Decisions in the editor

When a Sheet, Flow, or Scene is affected by accepted decisions that are not fully applied yet, its lightbulb shows an amber count. Hover over it to read a summary, such as "2 decisions about Mara · 1 to apply".

The **Explorations** dialog lists the **Decisions about** that content: first those still to apply, then open proposals, then those already applied or that need no change. The list includes the decisions that name the content in **Affects** and every decision of the sessions that explore it.

From each decision you can:

- open it in its session;
- select **Mark applied** to declare its state without leaving the dialog;
- select **Go apply** to work on it in the editor.

## Apply a decision

**Go apply** opens the affected content with the decision pinned under the editor header: its title, verb, conclusion, and session, next to the content you are about to change.

<img src="/images/docs/brainstorming/brainstorming-apply-banner.webp" alt="The Flow Act 3 endings open in its editor with the decision The player chooses who keeps the light under the header, offering Mark applied, Partially, and No change needed" loading="lazy">

Make your changes, then choose **Mark applied**, **Partially**, or **No change needed**, optionally with a short note. For five seconds after marking you can **Undo**, which restores the previous state. The banner goes away when you move to other content.

Storyarn never applies a decision for you and never checks the content to decide whether it was applied. The state is what your team declares.

## Notifications

Decisions notify the people who have to act, in the notifications inbox:

| When                                           | Who is notified                                              |
| ---------------------------------------------- | ------------------------------------------------------------ |
| A decision is proposed                         | The responsible person, who has to accept it                 |
| A decision is accepted                         | Its proposer, and everyone who started a discussion about it |
| An accepted decision has a next action         | The person the next action is assigned to                    |
| An affected piece of content is marked applied | The responsible person and the proposer                      |

You are never notified of your own actions. Mentions and replies in a decision's discussion arrive like any other comment notification.

<img src="/images/docs/brainstorming/brainstorming-inbox.webp" alt="The notifications inbox with two decisions marked applied and one decision proposed for you to accept" loading="lazy">

## The decisions dashboard

The **Decisions** tab of the Brainstorming dashboard lists every decision in the project, from every session.

- Filter by status: **Proposals**, **Accepted**, or **Withdrawn and superseded**.
- Filter by application: **Still to apply**, **Applied**, or **No change needed**.
- Turn on **Group by affected content** to see, for each Sheet, Flow, or Scene, the decisions about it and how many are still to apply.

<img src="/images/docs/brainstorming/brainstorming-decisions-dashboard.webp" alt="The Decisions tab of the Brainstorming dashboard grouped by affected content, with the Flow Act 3 endings and the Sheet Mara each listing the decision that affects them" loading="lazy">

## The command palette

Press **Cmd/Ctrl+K** and type the name of a Sheet, Flow, or Scene. Under **Jump to**, the palette lists the content and, below it, the decisions that name it, with their verb, status, and session.

<img src="/images/docs/brainstorming/brainstorming-palette.webp" alt="The command palette searching Mara and listing the Sheet, a Flow, and the decision The player chooses who keeps the light" loading="lazy">

Decisions follow the same access rules everywhere: you only see the decisions, sessions, and sources you are allowed to read.
