%{
translation_key: "brainstorming-decisions",
title: "What a Brainstorm Leaves Behind",
seo_title: "Brainstorming and Decisions in Narrative Design",
description: "Why brainstorming loses ideas during and after the session, and how Storyarn keeps a team's decisions attached to the characters, flows, and scenes they change.",
author: "Storyarn Team",
image: "/images/blog/brainstorming-decisions-reach-the-story.jpg",
image_alt: "A brainstorming round in Storyarn: a group of notes with its synthesis, and the round's decisions linked to the notes they came from",
tags: ["Brainstorming", "Narrative design", "Collaboration", "Production"]
}

---

A brainstorm can go well and still leave nothing behind.

The hour is lively. Forty notes cover the board, two endings survive the discussion, and everyone leaves agreeing that the lighthouse keeper wants forgiveness, not power. Three weeks later his character sheet still lists ambition as his defining trait, the writer reworking Act 3 is not sure which ending won, and nobody remembers who was going to change the flow. The ideas were fine. What got lost was the decision.

Brainstorming is older than most of the tools we use for it, and the research around it is unusually clear about where it fails: when a group talks too early, and when nobody carries the result into the work.

## Twice as many ideas

In 1953 Alex Osborn published _Applied Imagination_, the book that turned brainstorming into a method: go for quantity, hold back criticism, welcome wild ideas, combine and improve. In the 1957 edition he went further and claimed that the average person could think up twice as many ideas in a group as alone.

The experiments pointed the other way. In 1958, Taylor, Berry, and Block compared real groups with "nominal" groups, people who worked alone and whose ideas were pooled afterwards. The nominal groups produced nearly twice as many different ideas. In 1987, Michael Diehl and Wolfgang Stroebe [traced most of that loss](https://doi.org/10.1037/0022-3514.53.3.497) to production blocking: in a spoken session only one person talks at a time, and ideas fade while people wait their turn. A [1991 meta-analysis](https://doi.org/10.1207/s15324834basp1201_1) of twenty studies by Brian Mullen, Craig Johnson, and Eduardo Salas concluded that brainstorming groups are significantly less productive than nominal groups "in terms of both quantity and quality".

Groups also converge. Nicholas Kohn and Steven Smith [found](https://doi.org/10.1002/acp.1699) that brainstormers' ideas conformed to the ideas other participants had suggested, and that groups explored fewer kinds of ideas. And people rarely notice: Paul Paulus and his colleagues described an [illusion of group productivity](https://doi.org/10.1177/0146167293191009), in which members believe the group helped them more than it did.

None of this means teams should stop meeting. It means the order matters. Methods built on that insight have existed for more than fifty years. Bernd Rohrbach's 6-3-5 brainwriting, from 1969, has people write before anyone speaks. The [nominal group technique](https://doi.org/10.1177/002188637100700404) described by André Delbecq and Andrew Van de Ven in 1971 asks participants to work silently and independently first, and only then to share, discuss, and choose. Other people's ideas are not the problem; [they can prompt new ones](https://doi.org/10.1207/s15327957pspr1003_1) once everyone has had the chance to write their own.

## Choosing is the weak step

Generating ideas gets most of the attention, but choosing among them is harder than it looks. In a [2006 study](https://doi.org/10.1016/j.jesp.2005.04.005), Eric Rietzschel, Bernard Nijstad, and Wolfgang Stroebe found that when participants picked their best ideas, their selection was "not significantly better than chance".

A good choice also has to leave the room. We did not find a study that measures how often workshop decisions are lost, and we will not invent a number. The indirect evidence is consistent, though. A study of 92 recorded team meetings associated [action planning with team productivity](https://doi.org/10.1177/1046496411429599), and meeting researcher Steven Rogelberg [notes](https://www.stevenrogelberg.com/alternative-approach-that-could-be-a-game-changer) that attaching a name to a task in public increases follow-through. Whiteboard vendors say it too. A [Miro article](https://miro.com/blog/how-to-execute-ideas/) describes session ideas that "collect dust" once the session is over, and suggests sending them to Jira. A [Figma guide](https://www.figma.com/blog/the-five-stages-of-an-effective-brainstorm/) asks that someone be able to reopen the file weeks later "and see where you ended up", and to assign owners.

Software teams faced the same problem in another form. In 2011 Michael Nygard proposed [architecture decision records](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): short records with a status (proposed, accepted, and later deprecated or superseded) kept next to the code because "large documents are never kept up to date." The decision lives where the work happens.

## A narrative decision reaches far

In a narrative game, the distance between the meeting room and the work is longer. "Tobin wants forgiveness, not power" is not a task. It changes a character sheet, the conditions of a branching conversation, the ending that depends on them, perhaps a scene, and later the lines that go to translation and recording.

_Baldur's Gate 3_ shows that reach at a recent, large scale. During early access, Larian concluded that one companion's story was not working. At the studio's Panel From Hell in 2023, lead writer Adam Smith [explained](https://www.pcgamesn.com/baldurs-gate-3/rewritten-companion) that Wyll "had this incredibly compelling story, but we weren't telling it as well as we could have done", and that "pretty much every line of dialogue has been rewritten." In January 2026, senior writer Kevin VanOrd [added](https://kotaku.com/baldurs-gate-3-bg3-wyll-rewrite-cut-content-scene-story-2000658493) that the team "started over at a point when most of the other companion stories were fairly solid." A situation at the Red War College that was meant to involve Wyll heavily was cut, and when the new material had to be written, an unexpected illness kept VanOrd away from the studio for a long stretch. Wyll's content, he says, ended up "sparser than I'd have liked." The decision was the right one. It still had to reach every line of a fully voiced character and every scene that depended on him.

A general-purpose whiteboard does not know which character sheet or which flow a note is about. That is not a flaw; it is what makes a whiteboard good at everything. But it means the link between the agreement and the content lives in someone's memory, or in a ticket that describes the change instead of pointing at the content.

## How we approached it in Storyarn

Storyarn's brainstorming lives inside the project, next to the Sheets, Flows, and Scenes it talks about. It is deliberately narrow. Miro, FigJam, and other whiteboards remain better tools for open-ended workshops, diagrams, and anything outside the story, and we are not trying to replace them. We wanted a place where a narrative team's exploration ends in the content it changes.

A session is a canvas of notes divided into rounds, each with its own question. A round can be private: everyone writes alone and sees only grey placeholders for other people's notes until the facilitator reveals the round, or until the timer does when the round is set to reveal on time. That is the nominal-group order, write alone and then share, built into the canvas instead of depending on discipline. Related notes are gathered into groups with a written synthesis, which is where a direction starts to take shape.

A decision then records what the team agreed to do, in a shape meant to outlive the session: one verb (create, change, test, keep, or discard), up to five affected Sheets, Flows, or Scenes, a conclusion, an optional reason and next action, and the exact version of the notes it came from. The responsible person accepts it explicitly. There is no voting, and nobody else can accept on their behalf. Like a decision record, it can be revised, withdrawn, or superseded without losing its history.

The part that matters most comes after acceptance. The decision appears where the work is: as a count in the header of the affected editor, in a "Decisions about Mara" list inside that editor, as a banner beside the content when someone goes to apply it, as a notification for the person who has to act, on a dashboard that can group decisions by affected content, and in the command palette when you search for the character. Each affected Sheet, Flow, or Scene is then marked applied, partially applied, or as needing no change by an editor, usually whoever made the change.

The bridge also works the other way. From any Sheet, Flow, or Scene you can start an exploration with that content as its context, or resume the sessions already linked to it. The [brainstorming guides](/docs/brainstorming/brainstorming-overview) describe each piece in detail.

## What it does not do

Marking a decision applied is a statement from the team, not a verification. Storyarn never applies a decision to your content and never checks that a change was made. It records what was agreed and what people say they have done, and shows both to whoever opens the content.

The canvas holds text notes, shapes, connections, and groups. It has no templates, drawing tools, or embedded media, and we are not trying to compete with general-purpose whiteboards on those. If your team already runs good workshops elsewhere, the part worth bringing into Storyarn is the end: the decisions, and the content they change.

We would like to hear from teams who run story workshops. Where does the result of your sessions go today, and how does the rest of the team find out when a character changes?

## Sources and scope

The research cited here studies idea generation in controlled settings, mostly with students, and does not measure narrative teams. The developer statements and the vendor articles are qualitative examples, not measurements of how often decisions are lost; we found no study that measures that directly. Osborn's 1957 claim and the 1958 results of Taylor, Berry, and Block are cited as reported by Diehl and Stroebe (1987). Rohrbach's 6-3-5 method is cited by its original publication (_Absatzwirtschaft_, 1969), which we did not read directly. Larian's statements are quoted as reported by PCGamesN (from the Panel From Hell stream) and by Kotaku (from a Reddit AMA).

Product behavior was checked against Storyarn's current implementation of sessions, rounds, groups, and decisions on September 24, 2026. The third-party pages linked above were read on the same date.
