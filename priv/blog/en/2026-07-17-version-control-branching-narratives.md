%{
translation_key: "version-control-branching-narratives",
title: "Going Back Without Breaking the Story",
seo_title: "Version Control for Interactive Narrative",
description: "Why version control remains difficult for interactive narrative, and how Storyarn tries to recover content without breaking its relationships.",
author: "Storyarn Team",
image: "/images/blog/version-control-branching-narratives.svg",
image_alt: "Three moments in a connected story and a review that reveals a broken relationship before restoration",
tags: ["Version control", "Narrative design", "Collaboration", "Production"]
}

---

A restore can complete without errors and still break a story.

The conversation comes back. Its speaker does not. The condition is still in the graph, but the variable it queried no longer exists. The button said “restore”; what it recovered was only one piece of the past.

Almost nothing in an interactive story lives alone. A line may be connected to a translation and a recording. A choice depends on a variable. A character reappears across conversations, scenes, and documents that evolve at different speeds. Recovering text is simple. Recovering the meaning it acquired through everything around it is not.

Version control has spent decades trying to make change reversible. Its history helps explain why the problem becomes different when it reaches narrative design.

## From files to connected stories

In 1972, Marc Rochkind created SCCS at Bell Labs to control the source code of large programs. The [paper he published in 1975](https://doi.org/10.1109/TSE.1975.6312866) explained how to retain each change, record who made it, and retrieve any revision. Fifty years later, Rochkind acknowledged in a [retrospective](https://www.mrochkind.com/mrochkind/docs/SCCSretro2.pdf) that the system did not model how teams actually worked.

Later tools added branches, merges, and distributed collaboration. Although systems such as Git version repository snapshots, their usual comparison vocabulary remains organized around files and lines. Narrative design inherited that infrastructure and its mismatch: to a designer, the thing that changed is usually a conversation, a scene, or a decision connected to many others.

The Twine community was already describing this tension in 2014. Its `.tws` format retained the visual story map but was difficult to diff and merge. Twee offered Git-friendly text, but a round trip could [lose passage positions](https://twinery.org/archive/forum/discussion/1403/preserving-twine-metadata-in-twee-sources.html). In 2017, researchers from ETH Zurich, Disney Research, and Rutgers presented a [Story Version Control](https://la.disneyresearch.com/publication/story-version-control-and-graphical-visualization/) framework built from events and participants, with visual comparison, conflict detection, and story merging.

A dependable way back lets teams experiment, divide work, and revisit decisions without maintaining folders full of copies. In branching narrative, where one edit can alter playable paths, state, localization, and voice-over, version history is both a production safeguard and a source of creative freedom.

## Saving is not the same as going back

Persistence problems did not disappear with autosave. In 2016, Inky users reported [files whose contents had vanished](https://github.com/inkle/inky/issues/38). In 2024, a race between saving and the file watcher could delete a project when `Ctrl+S` was pressed rapidly; the [issue was fixed](https://github.com/inkle/inky/issues/508). In 2025, a [report with reproduction steps](https://github.com/inkle/ink/issues/946) described corruption in deeply nested Ink files. In 2026, a Twine report showed that launching Play, Test, or Export before a change appeared in the story map could use [the previous passage state](https://github.com/klembot/twinejs/issues/1689). These are qualitative cases, but they show that the question remains open.

Part of the confusion comes from using “safety” for several different mechanisms. Save persists the current state. Undo reverses a recent action. A backup survives loss. History preserves decisions across time and should explain what changes when one is recovered. A product can provide three of those layers and still leave a gap in the fourth.

Plain-text files and Git provide portability, authorship, and an application-independent format. They are a valuable foundation. Git can tell us which lines changed; on its own, it does not know whether a condition made a branch unreachable or whether a translation still belongs to its source.

## A story breaks between objects

Imagine that a designer restores Tuesday's version of a conversation. At that point Captain Ilya was its speaker, and the `trust_ilya` variable decided whether a response appeared. By Thursday, the character had been replaced, the variable renamed, and her lines had entered localization.

If the tool restores only the nodes, the canvas may look correct while hiding two missing dependencies and a disconnected translation. If it restores the whole project, the captain and variable return, but valid work created later may disappear as well. The difficulty is not choosing between a local and a global restore button. It is knowing which relationships belonged to that decision and which evolved independently.

In 2024, a team using Dialogue System for Unity asked how to stop multiple writers from overwriting one another. Support recommended separate databases and disjoint ID ranges. The user warned that renumbering them would break Lua references, and the [answer confirmed that preserving those IDs was the safe approach](https://forum.pixelcrushers.com/post/best-practices-for-dialogue-system-version-control-13719816). Versioning content also means preserving its identity.

The same limit appears elsewhere. LegendKeeper warns that reimporting content creates [new IDs and internal links](https://www.legendkeeper.com/changelog/legendkeeper-0-16-1-0/), while articy:draft X has fixed problems involving [deterministic serialization](https://www.articy.com/help/adx/Changes_4_2.html) and [locks and discarded work](https://www.articy.com/help/adx/RecentChanges.html). A recoverable file can still produce phantom changes or different references.

There has also been clear progress. In 2025, Arcweave launched [whole-project history](https://arcweave.com/whats-new/articles/project-history-is-now-live-for-team-workspaces) whose restore creates a new version instead of erasing later work. It is not a universal solution, but another choice of granularity. The useful question remains what a restore preserves: text, identity, relationships, authorship, and the future.

## How we approach the problem in Storyarn

Storyarn's history did not begin with this research, but these sources help us judge it. We version units a designer recognizes: Sheets, Flows, and Scenes. Revisions can be named and compared as structured changes without reading JSON. For Sheets, restoring through the interface retains the current state as a safety version and records the result. For Flows and Scenes, the interface lets users save current changes before restoring, but those two automatic entries are not yet created consistently. The system also inspects a subset of external relationships.

That local layer coexists with Trash and project snapshots. [Trash](/docs/project-management/recovery-and-trash) handles recent deletion without pretending it is a version. Project snapshots offer a broader recovery point when a problem crosses several areas. Keeping those mechanisms separate is deliberate: correcting one conversation should not require rolling back everyone else's valid work.

There are limits. The preflight does not cover every kind of reference, and automatic capture is not triggered uniformly by every edit. Project snapshots do not yet reproduce an exact moment in time: they do not recreate everything deleted, remove everything created later, or include every area of the platform. We do not present them as a complete rollback.

The direction is simple to state and difficult to implement: a version should correspond to a narrative unit a designer understands, preserve the present as a recoverable state, and explain its effect on identities and relationships before changing them. We may not be able to repair Captain Ilya, `trust_ilya`, and every translation automatically, but we should detect them before presenting an apparently correct canvas.

If you have encountered a case where restoring a version broke a reference, a translation, or someone else's work, we would like to hear about it. Real edge cases are what turn “going back” into something a team can trust.

## Sources and scope

The linked discussions and issue reports are qualitative examples, not measurements of frequency or overall evaluations of the products involved. We checked product behavior against official documentation available on July 17, 2026.

Statements about Storyarn were checked against its [entity history implementation](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/version_crud.ex), [dependency analysis](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/conflict_detector.ex), [project snapshots](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/builders/project_snapshot_builder.ex), and current tests.
