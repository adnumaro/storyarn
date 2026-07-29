# Flow dialogue typography

> Owner: Engineering
>
> Last reviewed: 2026-07-29
>
> Source of truth: `assets/css/screenplay.css` and the Flow dialogue editor components

The surviving `screenplay` and `sp-*` names describe the visual treatment of
Dialogue flow nodes. They do not represent a Screenplays domain or document
type.

## Current contract

- Dialogue pages use self-hosted Courier Prime at 12pt with a line height of 1.
- The paper surface is capped at 816px and uses 96px top/right/bottom padding
  with 144px left padding.
- Character cues are uppercased and offset 211px from the content origin.
- Parentheticals are italic, muted, offset 154px, and capped at 240px.
- Dialogue is offset 96px and capped at 336px.
- Speaker controls inherit the character-cue treatment.
- TipTap mentions intentionally use the application UI font, not Courier Prime.

These measurements are presentation constants for the Flow editor. Change this
document when the CSS contract changes; do not treat historical screenplay
formatting research as application requirements.
