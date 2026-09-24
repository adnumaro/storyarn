%{
title: "Brainstorming Overview",
category_label: "Brainstorming",
order: 1,
description: "Explore ideas with your team on a shared canvas and turn what you agree on into decisions that reach your sheets, flows, and scenes."
}

---

Brainstorming is where your team explores narrative ideas before they become production content. A {accent}session{/accent} is a shared canvas of notes, organized in rounds, where people write, group what belongs together, and record what they agreed to do.

<img src="/images/docs/brainstorming/brainstorming-board.webp" alt="A brainstorming session with a round header, a group of notes with its synthesis, a discarded note, a connection, and the round's decisions lane at the bottom" loading="lazy">

## Why brainstorm inside Storyarn

A general-purpose whiteboard is the right tool for freeform diagrams, workshops, and anything that lives outside your story. Brainstorming in Storyarn has a narrower job: it knows your project. A session can start from a Sheet, Flow, or Scene, and an agreement names the content it changes. That decision then appears in the editor of that content until someone marks it applied, so the outcome of a session does not stay behind on a board nobody reopens.

## How a session is organized

| Piece            | What it does                                                                                                                       | Read next                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Notes**        | Short contributions you write, move, shape, color, and connect on the canvas.                                                      | [Canvas and Notes](/docs/brainstorming/canvas-and-notes)                   |
| **Rounds**       | Horizontal bands of the canvas, each with its own question. A round can stay private until it is revealed and can run a countdown. | [Rounds, Privacy, and Timer](/docs/brainstorming/rounds-privacy-timer)     |
| **Groups**       | Frames around related notes, with a written synthesis of what they have in common.                                                 | [Groups and Synthesis](/docs/brainstorming/groups-and-synthesis)           |
| **Decisions**    | What the team agreed to do, to which content, and how far it has been applied.                                                     | [Decisions](/docs/brainstorming/decisions)                                 |
| **Explorations** | Sessions linked to a Sheet, Flow, or Scene, and the decisions about that content, shown from its editor.                           | [Decisions in Your Content](/docs/brainstorming/decisions-in-your-content) |

None of these pieces is mandatory. A session can be a single round of loose notes, or three rounds that end in accepted decisions. You add structure when it helps.

## Start a session

Select **New session** on the Brainstorming dashboard, or the **+** next to **Sessions** in the sidebar. The session opens straight away as "Untitled session", with one round and an empty canvas. Double-click anywhere to write your first note.

<img src="/images/docs/brainstorming/brainstorming-empty-session.webp" alt="A new, untitled brainstorming session with an empty canvas inviting you to double-click anywhere to write" loading="lazy">

Open **Session details and settings** from the sliders icon in the header to give the session a title, an objective, and some context. The objective and context are optional; they help people who join later understand what the session is for.

You can also start a session from the content you want to change. **Explore changes** in a Sheet, Flow, or Scene creates a session with that content as its starting context. See [Decisions in Your Content](/docs/brainstorming/decisions-in-your-content).

The command palette also works here: search a session by its title to open it, or run **New session** from anywhere in a project you can edit.

## The Brainstorming dashboard

The dashboard lists the open sessions of the project. A session with decisions shows a short summary, such as `4 decisions · 1 waiting for you · 1 to apply`, so you can see where your attention is needed without opening each one. The **Decisions** tab lists every decision in the project and is described in [Decisions in Your Content](/docs/brainstorming/decisions-in-your-content#the-decisions-dashboard).

<img src="/images/docs/brainstorming/brainstorming-dashboard.webp" alt="The Brainstorming dashboard with three sessions; one of them summarizes four decisions, one waiting for you and one to apply" loading="lazy">

The sidebar shows the same sessions. Expand a session to see its rounds, named after their questions, and its **For later** list. Use the filter at the top of the sidebar to switch between **Open**, **Archived**, and **Replaced** sessions.

## Roles in a session

A session has two responsibilities, both assigned in **Session details and settings**. Only people who can edit the project can hold them.

| Role               | What it means                                                                                                                                                                                                                                                                                |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Facilitator**    | Runs the session: edits its title and settings, writes each round's question, starts and closes rounds, makes a round private and reveals it, runs the timer, and archives the session. The person who creates a session is its first facilitator; the role can be handed to another editor. |
| **Decision owner** | The person suggested by default as responsible for new decisions. It gives no rights to manage the session.                                                                                                                                                                                  |

Everyone else participates according to their project role:

| Project role | In a session                                                                                                   |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| **Owner**    | Everything an editor can do, plus facilitating any session and reassigning either responsibility.              |
| **Editor**   | Creates sessions, writes notes, groups them, comments, proposes decisions, and marks how far they are applied. |
| **Viewer**   | Reads the sessions, notes, groups, and decisions they have access to. Cannot write.                            |

Permissions are checked on the server for every change, not only hidden in the interface.

## Archive a session

When a session is finished, the facilitator or the project owner can select **Archive session** in **Session details and settings**. An archived session stays readable, with its notes, groups, decisions, and history. Its decisions keep appearing in the content they affect.

Archiving also ends the privacy of every private round: from then on each counts as revealed, although notes that were never shared are not published. A facilitator can **Reopen session** later to keep working.
