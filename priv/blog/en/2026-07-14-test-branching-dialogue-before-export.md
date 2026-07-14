%{
title: "How to Test Branching Dialogue Before Exporting It to Your Game Engine",
description: "A practical workflow for testing branching dialogue, conditions, variables, and dead ends before narrative content reaches your game engine.",
author: "Storyarn Team",
tags: ["Branching dialogue", "Narrative design", "Game development"]
}

---

Branching dialogue rarely fails because a writer cannot write a convincing line. It fails because the logic around that line becomes difficult to see: a choice appears under the wrong condition, a variable changes too early, a branch never reconnects, or a valid route ends without a destination.

Finding those problems after the dialogue has been exported to a game engine is expensive. At that point, narrative logic is mixed with scene setup, UI, animation, audio, and gameplay code. A small content error can look like an integration bug, and every correction has to travel through the export and implementation loop again.

A better approach is to treat a branching conversation as an executable system and test it before export. The goal is not to predict every player decision. It is to prove that the dialogue behaves correctly for the states and routes you intentionally designed.

This article describes a repeatable workflow for doing that.

## 1. Define the states that control the conversation

Before testing individual lines, list the state that can change what the player sees. This usually includes:

- quest stages;
- relationship or reputation values;
- inventory flags;
- previous choices;
- character availability;
- one-time conversation markers.

Keep this list smaller than the complete game state. You only need the variables that influence the flow under test.

For each variable, record its meaningful values and its default. A boolean such as `met_the_archivist` has two obvious states. A reputation score is more useful when represented by the thresholds the dialogue actually checks: below 20, from 20 to 49, and 50 or higher.

This turns an unbounded testing problem into a finite set of narrative states.

## 2. Build a route matrix, not a list of every combination

Testing every possible combination of variables is usually unrealistic. Instead, create a route matrix around the decisions that change the flow.

For each important choice or condition, include at least:

1. the normal route;
2. the route immediately below a threshold;
3. the route exactly at the threshold;
4. the route above the threshold;
5. the fallback route when no preferred condition is met.

Suppose a response requires `reputation >= 20`. Testing values 19, 20, and 21 gives much more useful coverage than testing three arbitrary values. It checks the boundary where logic errors are most likely to appear.

The same principle applies to compound conditions. If a choice requires both a key and a completed quest, test the two successful values together, then remove each requirement independently. That proves the condition is using **and** rather than **or**, and that neither part is being ignored.

## 3. Test structure before prose

It is tempting to read the conversation from top to bottom and edit the writing as you go. That is valuable later, but it is a weak first test because polished prose can hide broken structure.

Start by checking the flow as a graph:

- Does every intended entry point lead somewhere?
- Can every visible response reach a valid next node?
- Are there branches with no exit?
- Can a loop repeat forever without changing state?
- Do branches reconnect where the design expects them to?
- Are shared subflows entered and exited correctly?

In Storyarn, the [flow editor](/docs/narrative-design/flows-overview) keeps dialogue, conditions, instructions, hubs, jumps, and subflows in the same visual model. Use that overview to inspect the shape of the conversation before running it.

A structurally valid flow is not necessarily narratively correct, but structural mistakes are faster to fix when they are separated from writing feedback.

## 4. Execute one path at a time

Now run the dialogue from its entry point and make one deliberate choice at each branch. Record:

- the initial state;
- the choices selected;
- the nodes visited;
- every variable change;
- the final state and exit.

This record does not need to be a large test document. A short identifier such as `hostile-no-key-quest-open` is enough if the setup and expected result are clear.

Use the [Storyarn debugger](/docs/narrative-design/debug-mode) to step through the flow node by node. The active path, conditions, and variable state should make it possible to answer three questions at every step:

1. Why is this response available?
2. Why was this branch selected?
3. What changed before the next decision?

If any answer depends on guessing, the flow is not yet easy enough to debug.

## 5. Verify choices in both directions

Every conditional choice needs two tests: one where it should appear and one where it should not.

Only testing the successful route proves that the condition can become true. It does not prove that the choice is hidden or disabled when the condition is false. This is a common source of leaks, especially when dialogue has been copied and adapted from another branch.

For each response, verify:

- its text is attached to the intended speaker and node;
- its visibility condition uses the right variable;
- the boundary operator is correct (`>`, `>=`, `==`, and so on);
- selecting it applies the expected instructions;
- it continues to the intended destination;
- it cannot be selected in an invalid state.

Pay particular attention to fallback choices such as “Leave” or “Ask about something else.” They may look unimportant, but they prevent the player from becoming trapped when all specific choices are unavailable.

## 6. Check state changes at the moment they happen

A correct value applied at the wrong time is still a bug.

Imagine that accepting a mission sets `mission_started = true`. If that instruction runs before the player confirms the choice, another branch may react as though the mission has already started. If it runs after the conversation exits, the engine may load the next scene before the state is available.

Step through every instruction that changes state and verify:

- the previous value;
- the node that applies the change;
- the new value;
- which later condition first consumes it;
- whether reset or replay behavior is intentional.

This is where testing outside the engine saves the most time. The narrative team can establish whether the content model is correct before an engineer investigates integration code.

## 7. Try to break the flow deliberately

Happy paths prove that the designed route works. Adversarial paths reveal what happens when assumptions fail.

Useful destructive tests include:

- entering a subflow with an unexpected variable value;
- revisiting a supposedly one-time conversation;
- selecting choices in a different order;
- reaching a hub after all of its optional branches are exhausted;
- starting from a node deep in the flow;
- resetting midway through a state change;
- following the shortest possible route to the exit.

The purpose is not to invent impossible player behavior. It is to challenge hidden assumptions in the content. If a state is truly impossible, document which system guarantees it. Otherwise, give the flow a safe fallback.

## 8. Separate narrative QA from engine integration QA

Once the dialogue passes its internal tests, export it and run a smaller integration suite in the engine. The two stages answer different questions.

Narrative QA should establish that:

- choices and conditions behave correctly;
- variables change as designed;
- every supported path reaches a valid result;
- the conversation reads coherently in context.

Engine integration QA should establish that:

- exported identifiers resolve correctly;
- the runtime maps variables to the intended game state;
- UI, input, audio, camera, and animation react correctly;
- saving and loading preserve the relevant state;
- engine-specific callbacks fire at the right time.

When these responsibilities are mixed, every failure has a large search area. When they are separated, the team knows whether to inspect content or integration first.

The [import and export overview](/docs/import-export/import-export-overview) explains how Storyarn packages connected project data for downstream runtimes.

## A practical pre-export checklist

Before handing a branching conversation to the engine, confirm that:

- [ ] every entry point reaches a valid path;
- [ ] every visible response has a destination;
- [ ] conditional choices were tested as both available and unavailable;
- [ ] threshold values were tested immediately below, at, and above the boundary;
- [ ] state changes happen on the intended node;
- [ ] loops have an exit or an intentional repeat condition;
- [ ] fallback choices prevent dead ends;
- [ ] shared subflows return to the correct caller;
- [ ] representative happy, alternate, and adversarial routes pass;
- [ ] the final state matches what the next scene or system expects.

## Make the export a delivery step, not a debugging step

Export should be the moment a tested narrative moves into its runtime, not the first time anyone discovers how the narrative behaves.

By defining meaningful states, testing boundaries, executing representative paths, and verifying state changes before integration, narrative teams remove ambiguity from the handoff. Writers can own the correctness of dialogue logic, while engineers can focus on runtime behavior.

That separation shortens feedback loops and makes branching content safer to change as the project grows.
