%{
title: "Introducing Storyarn: A Connected Narrative Design Platform",
seo_title: "Introducing Storyarn: Narrative Design Platform",
description: "Storyarn is a narrative design platform that keeps world data, branching dialogue, scenes, testing, localization, and export in one connected project.",
author: "Storyarn Team",
image: "/images/docs/project-dashboard-current.png",
image_alt: "Storyarn project dashboard showing sheets, flows, scenes, localization progress, warnings, and recent activity in one connected project",
tags: ["Storyarn", "Narrative design", "Game development"]
}

---

Today we are opening Storyarn to everyone.

Storyarn is a narrative design platform for teams building interactive stories. It connects world data, branching dialogue, spatial scenes, testing, localization, and export inside one project, so the relationships that make a story work do not disappear between tools.

Registration is open, no invitation is required, and Storyarn is free during early access.

This first post is not a tutorial. It is the product decision behind the platform: an interactive story is not a stack of documents. It is a system, and the connections inside that system deserve to be first-class parts of the creative work.

## The problem is not writing the line

Consider a short exchange in which the player asks a character about a hidden location.

The response only appears when that character trusts the player. Choosing it changes the state of a quest. The location becomes available on the map. The line needs translation, its voice-over needs tracking, and the final result has to reach the game in a form the runtime can understand.

Writing the sentence is the smallest part of that decision.

In a typical production workflow, the character may be described in one document, the trust value kept in a spreadsheet, the conversation drawn in a graph, the location stored in a map, and the translated text managed in another file. An engineer eventually receives identifiers and conditions that have travelled through all of them.

Every tool can be good at its own job and the workflow can still be fragile. The threshold changes in the spreadsheet but not in the dialogue. The source line changes after translation. The map shows a location that no reachable branch can reveal. A graph remains syntactically valid while pointing at an idea the rest of the project has already abandoned.

Teams usually bridge those gaps with naming conventions, internal wikis, review meetings, and people who remember where every decision was copied. That memory works until a project grows, a deadline compresses, or the person carrying the context needs to focus elsewhere.

Storyarn starts in that gap between tools.

## A connected narrative model

The central idea is straightforward: the character, the trust value, the conversation, the location, and the localized line should not be five unrelated representations of the same story decision.

In Storyarn they can belong to the same model.

[Sheets](/docs/world-building/sheets-overview) describe the structured parts of a world: characters, places, factions, items, quests, and the fields that matter to the project. [Flows](/docs/narrative-design/flows-overview) use that data directly in dialogue, responses, conditions, and instructions. [Scenes](/docs/scene-design/scenes-overview) give narrative content a spatial context. Localization retains the identity and source of player-facing text instead of receiving an anonymous pile of strings.

These are not separate mini-products placed behind one login. A field defined for a character can be read by a condition in a Flow and changed by an instruction. A scene can lead into that Flow during exploration. When the source dialogue changes, the localization workflow can show that the existing translation now needs attention.

The connection is the product.

<figure>
  <img src="/images/docs/project-dashboard-current.png" alt="Storyarn project dashboard bringing world data, flows, scenes, localization, validation, and activity into one project" loading="lazy">
  <figcaption>A project is treated as one narrative system, not as a folder of unrelated files.</figcaption>
</figure>

This changes the questions a team can ask. Not only “where is this line?”, but “what makes it available?”, “what does it change?”, “where can the player encounter it?”, “which translation came from it?”, and “will the exported project still carry those relationships?”

It also keeps the creative intent close to the work. The graph does not need a separate paragraph explaining what a condition was supposed to mean. The world document does not have to duplicate the state that the dialogue actually uses. The handoff does not begin by reconstructing the model from filenames and conventions.

## Follow one decision through the project

Return to the hidden location.

The character’s trust value lives on a structured Sheet rather than inside an isolated note. The conversation checks that exact value. If the requirement is met, the response becomes available; choosing it can update the quest and reveal the location. The scene gives the location a place in the world, and the dialogue keeps its source identity as it moves into localization.

The important point is not that Storyarn has a sheet editor, a node canvas, and a map. It is that the same decision can travel through all three without being translated into a new private convention at every boundary.

<figure>
  <img src="/images/docs/flows-editor-current.png" alt="Storyarn Flow editor showing connected dialogue, response, condition, instruction, and exit nodes" loading="lazy">
  <figcaption>A Flow keeps the writing beside the state and consequences that make it interactive.</figcaption>
</figure>

That does not remove complexity. Branching narrative has state, dependencies, reusable structures, delayed consequences, and edge cases. Hiding those things would make the tool feel simpler while making production less reliable.

Storyarn’s job is to keep that complexity visible and navigable. A writer can stay with the conversation while a narrative designer inspects its rules. A localization team can see the source context. An engineer can receive a coherent model instead of a collection of files whose relationships only existed in someone’s head.

Different disciplines do not need identical interfaces. They do need to be looking at the same story.

## Test the story before the engine

An interactive story is not complete because every node has text. It has to execute.

Storyarn’s [Story Player](/docs/narrative-design/flows-overview#story-player) runs a Flow as the player would experience it, using its real conditions and state changes. The [Debugger](/docs/narrative-design/debug-mode) exposes the logic underneath: the active path, current variables, breakpoints, and the reason a branch was or was not reached.

Those are different kinds of feedback. The Story Player helps a team judge pacing, choice, and context. The Debugger helps it understand behavior.

<figure>
  <img src="/images/docs/flows-debug-current.png" alt="Storyarn debug mode showing the active narrative path, execution console, and live project variables" loading="lazy">
  <figcaption>The narrative can be played and inspected while the full design context is still available.</figcaption>
</figure>

The game engine still owns runtime reality. UI, animation, audio, saving, input, and the final integration must be tested there. But the engine should not be the first place a narrative designer learns that a branch is unreachable or a condition reads the wrong value.

Before [export](/docs/import-export/import-export-overview), Storyarn validates the connected project for broken references, unreachable paths, missing entry points, incomplete content, and other issues that are easier to resolve while the narrative context is still present. It can then prepare the project for formats including Ink, Yarn Spinner, Unity Dialogue System, Godot Dialogic, Unreal Engine, and articy:draft.

Export does not eliminate integration work. It gives that work a better source.

## Open beta is where the model meets real projects

Storyarn can already structure worlds, build and run branching Flows, map narrative spaces, manage localization, validate projects, and prepare exports. It is also an open beta: features will change, rough edges will surface, and real productions will challenge assumptions that tidy examples never reach.

That is why we are opening it now.

We want to learn where narrative teams still have to leave the platform. Which spreadsheet remains indispensable? Which relationship cannot be expressed? Which handoff still requires a private explanation? Which part of a writer’s process feels constrained instead of supported?

Storyarn is being built for narrative designers, game writers, world builders, localization teams, and small studios that need more than a dialogue editor without wanting their creative process buried beneath enterprise machinery.

We are not trying to make interactive narrative look simpler than it is. We are building a place where its complexity can stay connected, testable, and understandable from the first idea to the game.
