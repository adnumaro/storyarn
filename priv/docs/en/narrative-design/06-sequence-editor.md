%{
title: "Sequence Editor",
category_label: "Narrative Design",
order: 6,
description: "Compose images, sound and dialogue, then test the scene in the same workspace."
}

---

Open a flow and press **Play** in its toolbar. The visual editor appears above the node canvas. Select a dialogue to work on its composition. **Stop** in the toolbar returns to the full node canvas.

Drag the divider to resize the two views. Resize the Library and inspector from their edges, or hide them to give the stage more room. Fullscreen expands the same workspace; it does not open another page.

## Build the composition

Use **Sheets** to find character portraits and gallery images, or **Assets** to browse project images. Choose whether to add a character, backdrop, prop or overlay. Drag an image onto the stage or select it in the library. New images appear above existing layers.

You can also upload images here. Dropping files on the stage saves them in Assets and adds them to the current dialogue; dropping them in the library only saves them. When optimization is offered, Storyarn explains that it keeps the original and creates a lighter web image. The library shows the lighter image instead of displaying both copies.

Move images directly, resize them with the handles, or enter precise position and size values in the inspector. The frame always shows what playback includes: image pixels outside it are hidden, while selection handles remain available. Use the layer list to select an obscured image, reorder layers, hide a layer or lock its position while editing.

**Continues from** chooses the composition to inherit. Changes apply to this dialogue and dialogues that inherit from it. Resetting an inherited property reveals the source value again. Removing an inherited layer hides it here without deleting it from its source.

## Audio and voice

The inspector's **Audio** tab manages music, ambience and sound effects. Select or upload a recording, preview it, set its volume or remove it from this intervention. Music and ambience loop; sound effects play once.

Dialogue voice comes from the recording attached to the dialogue. The audio tab previews that recording; the dialogue inspector manages its attachment. Background audio and dialogue voice remain separate.

## Try the scene

**Preview** in the workspace starts playback from the selected dialogue. Continue, choose a response, go back or restart in the same view. Background music continues between dialogues when its source is unchanged; continue interrupts the previous voice immediately. If the browser blocks audio, use **Enable audio**.

Choose a content language to check translated dialogue, responses and voice. Status labels identify missing or outdated translations and recordings. Source text is shown when a translation is missing; a missing target-language voice stays silent.

**Debug** follows the existing Flow evaluator. Its Composition tab explains which dialogue supplies each layer or audio track, including overrides and removals. Use Variables and the other Debug tabs to check narrative conditions.

## Review with your team

Open **Comments** in the workspace to discuss the selected dialogue. These are the same threads available on its Flow node. Replies, mentions and resolution stay together, including in fullscreen. Comments refer to the intervention as a whole.

## Branches and recovery

Use a **Condition** and separate dialogue nodes when different decisions need different images, direction or voice. A dialogue has one explicit composition source, even where branches merge. Composition does not change according to the path taken to reach it.

Undo and redo include visual and audio changes. Flow versions and project snapshots preserve the composition and its asset references. Export formats for other tools may warn that they cannot represent these visual compositions; use native snapshots for a complete project round trip.

This editor creates static scenes. It does not include an animation timeline or video.
