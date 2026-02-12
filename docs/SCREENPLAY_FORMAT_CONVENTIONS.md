# Screenplay Format Conventions

> Industry-standard formatting rules for screenplays (US spec).
> Reference for Storyarn's screenplay editor rendering.
>
> **Primary reference:** *The Hollywood Standard* by Christopher Riley.

---

## 1. Typography

| Property            | Value                                                                     |
|---------------------|---------------------------------------------------------------------------|
| Font                | Courier, 12pt (monospaced, fixed-pitch)                                   |
| Accepted variants   | Courier New, Courier Final Draft, **Courier Prime** (modern, open-source) |
| Pitch               | 10 characters per inch (horizontal)                                       |
| Vertical density    | 6 lines per inch (vertical)                                               |
| Line spacing        | Single-spaced (within elements)                                           |
| Text color          | Black only                                                                |
| Paper color         | White (see Section 12 for revision colors)                                |
| Text alignment      | Left-justified, ragged right (never fully justified)                      |

**Why Courier?** Monospaced fonts ensure consistent character width, which maintains the industry rule: **1 page ≈ 1 minute of screen time**. This ratio depends on fixed-width characters to remain accurate.

**Courier Prime** is a modern redesign by John August (screenwriter of *Big Fish*, *Charlie's Angels*). It matches the metrics of Courier and Courier Final Draft exactly (same 10-pitch, same line height) but has improved readability. Free and open-source via Google Fonts.

**Courier New warning:** Courier New is slightly taller than standard Courier, which causes scripts to run longer (a 109-page script in Courier/Courier Final Draft can balloon to ~129 pages in Courier New). Avoid it if page count accuracy matters.

---

## 2. Page Setup

| Property       | Value                                    |
|----------------|------------------------------------------|
| Paper size     | US Letter (8.5" x 11" / 215.9 x 279.4mm) |
| Lines per page | ~54-56 (excluding page number)           |
| Page rule      | **1 page ≈ 1 minute of screen time**     |
| Printing       | Single-sided only                        |

### 2.1 Page Margins

| Edge    | Margin                                              |
|---------|-----------------------------------------------------|
| Top     | 1" (first content line begins here)                 |
| Bottom  | 1" (flexible, ~0.5"–1" depending on page breaks)    |
| Left    | 1.5" (accommodates 3-hole punch binding)            |
| Right   | 1" (flexible: 0.5"–1.25", ragged right)             |

### 2.2 Page Numbers

- Position: top-right corner, **0.5" from top**, flush with right margin.
- Format: number followed by a period (e.g., `2.`).
- First page of the script has **no page number**; numbering starts on page 2.
- Title page has no page number.

### 2.3 Scene Numbers (Shooting Scripts Only)

- **Spec scripts** (for submission): no scene numbers.
- **Shooting scripts** (for production): scene numbers appear on **both sides** of the scene heading.
  - Left scene number: 0.75" from left page edge.
  - Right scene number: 1" from right page edge (7.5" from left edge).
- Scene numbers are sequential integers. Inserted scenes use letters (e.g., `42A`).

---

## 3. Element Measurements

All measurements are from the **left edge of the page** (not from the left margin).

Courier 12pt = 10 chars/inch. Width in characters = width in inches x 10.

### 3.1 Primary Measurement Standard (Final Draft / Modern)

This is the standard used by **Final Draft**, **Highland**, **Fade In**, and most modern screenwriting software.

| Element          | Left edge | Right edge | Width  | ~Chars | Case / Style                             |
|------------------|-----------|------------|--------|--------|------------------------------------------|
| Scene Heading    | 1.5"      | 7.5"       | 6.0"   | 60     | ALL CAPS                                 |
| Action           | 1.5"      | 7.5"       | 6.0"   | 60     | Normal (present tense)                   |
| Character (cue)  | 3.7"      | 7.5"       | 3.8"   | 38     | ALL CAPS                                 |
| Dialogue         | 2.5"      | 6.0"       | 3.5"   | 35     | Normal                                   |
| Parenthetical    | 3.1"      | 5.6"       | 2.5"   | 25     | (lowercase, in parentheses)              |
| Transition       | 6.0"      | 7.5"       | 1.5"   | 15     | ALL CAPS, right-aligned, ends in `TO:`   |

### 3.2 Alternate Measurement Standard (Story Sense / Traditional)

Some older references and software use slightly different indents:

| Element          | Left edge | Right edge | Width  |
|------------------|-----------|------------|--------|
| Character (cue)  | 4.2"      | 7.5"       | 3.3"   |
| Dialogue         | 2.9"      | 6.2"       | 3.3"   |
| Parenthetical    | 3.6"      | 5.6"       | 2.0"   |

> **Note:** Both standards produce valid, industry-accepted screenplays. The differences are small (0.4"–0.5"). Final Draft's defaults (Section 3.1) are the most widely used today. Choose one and be consistent.

---

## 4. Element Descriptions

### 4.1 Scene Heading (Slug Line)

Marks a change of location or time. Always ALL CAPS.

**Format:** `INT./EXT. LOCATION - TIME OF DAY`

**Prefixes:**
- `INT.` — Interior
- `EXT.` — Exterior
- `INT./EXT.` or `I/E` — Both (e.g., doorway scenes)
- `EST.` — Establishing shot (rare)

**Time values:** `DAY`, `NIGHT`, `DAWN`, `DUSK`, `MORNING`, `AFTERNOON`, `EVENING`, `LATER`, `CONTINUOUS`, `MOMENTS LATER`

**Examples:**
```
INT. OFFICE - DAY
EXT. CITY PARK - NIGHT
INT./EXT. CAR - DAWN
INT. BATHROOM, KEVIN'S HOUSE - MORNING
```

**Rules:**
- Blank line before and after.
- Sub-locations separated by comma: `INT. KITCHEN, SMITH HOUSE - DAY`
- No period after time of day.
- Can optionally be **bold** and/or **underlined** (common in TV scripts, acceptable in features if consistent).

### 4.2 Action (Description / Direction)

Describes what the audience sees and hears — the visual narrative. Always written in **present tense**.

**Rules:**
- Starts at left margin (1.5").
- Keep blocks concise (ideally 4-5 lines max). Use white space.
- Capitalize: character names on **first introduction**, important SOUNDS, critical PROPS.
- Blank line between action paragraphs.
- Avoid "widow words" (single word dangling on the last line of a paragraph).

**Example:**
```
The door CREAKS open. JAIME (30s, weathered coat, tired eyes)
steps inside. He scans the room.
```

### 4.3 Character (Cue)

The name of the speaking character, positioned above their dialogue.

**Rules:**
- ALL CAPS.
- Left-aligned at its indent (NOT centered — a common misconception).
- Indented to 3.7" from left edge (see Section 3).
- No colon after the name.
- Must have a blank line before it (separating from action or previous dialogue block).
- No blank line after it (dialogue or parenthetical follows immediately).

**Extensions** — appear in parentheses after the name:
- `(V.O.)` — Voice Over (narrator, internal monologue, phone calls heard on speaker)
- `(O.S.)` — Off Screen (character present in the scene but not visible)
- `(O.C.)` — Off Camera (same as O.S., used in multi-camera TV)
- `(CONT'D)` — Continuation (see Section 6)
- `(SUBTITLED)` — Dialogue in a foreign language, shown with subtitles
- `(ON PHONE)` — Sometimes used as extension, sometimes as parenthetical
- `(PRE-LAP)` — Audio begins before the visual cut

**Examples:**
```
JAIME
JAIME (V.O.)
MARIA (O.S.)
JAIME (CONT'D)
```

### 4.4 Dialogue

What the character says. Positioned directly below the character cue.

**Rules:**
- Indented to 2.5" from left, max width ~3.5" (right edge at ~6.0").
- Normal case (not all caps). Never use ALL CAPS within dialogue.
- Left-aligned (not centered).
- No blank line between character cue and dialogue.
- No blank line between parenthetical and dialogue.
- Spell out all numbers in dialogue (for timing accuracy).
- **Interruption:** use an em-dash or `--` at the end of the cut-off line.
- **Trailing off:** use an ellipsis `...` at the end.

**Example:**
```
                      JAIME
            I don't think we should go
            in there. Not tonight.
```

### 4.5 Parenthetical

Brief acting direction placed within a dialogue block. Used sparingly.

**Rules:**
- In parentheses, lowercase.
- Indented to 3.1" from left, max width ~2.5".
- Placed between character cue and dialogue, or between dialogue lines.
- Should be short (a few words, not full sentences).
- If the direction is longer than a few words, use an action line instead.

**Common uses:**
- Tone: `(whispering)`, `(angry)`, `(sarcastic)`
- Action within dialogue: `(pause)`, `(beat)`, `(to Maria)`
- Delivery: `(in Spanish)`, `(reading from note)`

**Example:**
```
                      JAIME
                 (whispering)
            I don't think we should go
            in there.
                 (beat)
            Not tonight.
```

### 4.6 Transition

Indicates how one scene cuts to the next. Right-aligned, ALL CAPS.

**Rules:**
- Indented to 6.0" from left.
- ALL CAPS, typically ends in `TO:` (with a colon).
- Blank line before and after.
- Use sparingly — modern screenplays often omit `CUT TO:` since it's implied.
- **Exception:** `FADE OUT.` ends with a **period** (not a colon).
- **Exception:** `FADE IN:` is placed at the **left action margin** (1.5"), not right-aligned. Any transition ending with `IN:` is left-aligned.

**Common transitions:**
- `CUT TO:` (implied, often omitted)
- `SMASH CUT TO:`
- `MATCH CUT TO:`
- `DISSOLVE TO:`
- `FADE TO:`
- `FADE IN:` (opening of screenplay, **left-aligned**)
- `FADE OUT.` (closing, right-aligned, ends with **period**)
- `FADE TO BLACK.`
- `INTERCUT:`
- `TIME CUT:`

### 4.7 Dual Dialogue

Two characters speaking simultaneously, rendered side by side.

**Rules:**
- Both dialogue blocks share the same horizontal space, split into two columns.
- Each column has its own character cue, optional parenthetical, and dialogue.
- Used to show overlapping or simultaneous speech.
- In Fountain syntax, indicated by `^` after the second character name.

**Example (conceptual layout):**
```
     ALICE                          BOB
     (excited)
I got the job!               That's great news!
```

**Note:** Some formatting guides discourage dual dialogue as it's hard to convey timing on the page. Use when the simultaneity is dramatically important.

### 4.8 Page Break / Act Break

A visual separator indicating a new act or structural division.

**Rules:**
- Centered text, ALL CAPS, often **bold** and **underlined**: `END OF ACT ONE`, `ACT TWO`, etc.
- Each act begins on a new page.
- In Fountain: three or more `===` on a dedicated line.
- Primarily used in TV scripts (see Section 10).

### 4.9 Title Page

The first page of the screenplay, not counted in page numbers.

**Layout (vertical positioning):**
- **Title** — centered horizontally, approximately 1/3 down the page (~3.5" from top). ALL CAPS or Title Case, may be **underlined**.
- **Credit line** — centered, 1-2 lines below title. e.g., "Written by" or "Screenplay by"
- **Author name(s)** — centered, 1 line below credit.
  - `&` (ampersand) = writing team (wrote together)
  - `and` = sequential writers (different drafts)
- **Source** — centered, 1-2 lines below author. "Based on..." (if applicable)
- **Draft info** — bottom-left (1.5" from left edge), 2" from bottom. Date, draft number.
- **Contact info** — bottom-right or bottom-left (opposite side of draft info). Name, email, phone.

**Notes:**
- No page number on the title page.
- Left margin is **1.0"** on the title page (not the 1.5" used in the body).
- Keep it clean — no images, logos, or decorative elements.
- Spec scripts often omit the draft date to keep the script feeling "fresh."
- No copyright notice (viewed as amateurish by industry professionals).

### 4.10 Notes

Writer's annotations not intended for the final script.

**Rules:**
- Not visible in formatted output (authoring tool only).
- In Fountain: `[[This is a note]]`

### 4.11 Section Headings

Structural organizational headers (e.g., "ACT ONE", "SEQUENCE B").

**Rules:**
- Used for document outline/navigation, not rendered in formatted output.
- In Fountain: `# Act One`, `## Sequence B` (Markdown-style).

### 4.12 Shot (Camera Direction)

Specifies a camera angle or shot within a scene. ALL CAPS, left-aligned at the action margin.

**Examples:**
```
ANGLE ON - the broken window
CLOSE UP - Jaime's hand
INSERT - the letter
```

**Rules:**
- Use very sparingly in spec scripts — directing is the director's job.
- More common in shooting scripts.
- Formatted similarly to a scene heading (ALL CAPS, left margin) but does NOT include INT./EXT.

---

## 5. Text Emphasis (Bold, Italic, Underline)

Standard screenplay format uses emphasis **very sparingly**. There are no strict rules about when to use emphasis, but strong conventions exist:

### 5.1 ALL CAPS (Most Common)

| Usage                        | Example                                 |
|------------------------------|-----------------------------------------|
| Scene headings               | `INT. OFFICE - DAY`                     |
| Character cues               | `JAIME`                                 |
| Transitions                  | `CUT TO:`                               |
| Character first introduction | `JAIME (30s, tired eyes) enters.`       |
| Important sounds/SFX         | `The door SLAMS shut.`                  |
| Critical props               | `She picks up the GUN.`                 |

### 5.2 Bold

- **Least standardized.** Optional, use with restraint.
- Commonly used for scene headings (especially in TV scripts).
- Can be used for dramatic visual emphasis in action lines.
- Some writers bold slug lines for scanability — acceptable if consistent.

### 5.3 Italic

- Internal character thoughts (rare — usually handled via V.O.).
- Foreign language dialogue (with a note on first occurrence: "NOTE: All dialogue in Italian is shown in italics.").
- Sung lyrics within dialogue.
- Specific non-visual emphasis in action.

### 5.4 Underline

- Least commonly used.
- Sometimes used for scene headings (especially TV scripts).
- Additional emphasis when other techniques (caps, bold) are already in heavy use.
- Title on the title page is sometimes underlined.

**General principle:** If a reader can't understand the emphasis from context alone, the writing needs revision — not more formatting.

---

## 6. CONT'D (Continued)

Two distinct uses:

### 6.1 Dialogue Continuation (Same Speaker, Interrupted)

When the same character speaks, is interrupted by action, and speaks again — the second character cue gets `(CONT'D)`.

```
                      JAIME
            I need to tell you something.

Jaime paces the room.

                      JAIME (CONT'D)
            It's about what happened last night.
```

**Rules:**
- Automatic in most screenwriting software.
- Only applies when interrupted by action, NOT by another character's dialogue.
- A scene heading break **resets** continuation — no CONT'D across scenes.
- Transitions also reset continuation.
- Case-insensitive comparison of character names (ignore extensions like V.O., O.S.).
- Multiple extensions combine: `JAIME (V.O.) (CONT'D)`

### 6.2 Page-Break Continuation (MORE / CONT'D)

When dialogue is split across a page break:

**Bottom of page:**
```
            I need to tell you something
            important about what happened
                      (MORE)
```

**Top of next page:**
```
                      JAIME (CONT'D)
            last night at the warehouse.
```

**Rules:**
- `(MORE)` is centered below the last dialogue line on the page, at the character cue margin.
- `(CONT'D)` is appended to the character cue at the top of the next page.
- If the character already has an extension (e.g., V.O.), it becomes: `JAIME (V.O.) (CONT'D)`
- Never break mid-sentence if avoidable; break only at sentence boundaries.
- At least 2 lines of dialogue must appear before the break.

### 6.3 Scene CONTINUED (Spec vs. Shooting Scripts)

When a scene spans a page break, shooting scripts mark it with `(CONTINUED)` at the bottom and `CONTINUED:` at the top of the next page.

- **Spec scripts:** OMIT scene `CONTINUED` / `(CONTINUED)`. They clutter the page and are not needed.
- **Shooting scripts:** Include them. `(CONTINUED)` at bottom-left margin, `CONTINUED:` at top-left margin next to the scene number.

This is **different** from character `(CONT'D)` — do not confuse the two.

---

## 7. Spacing Rules

| Between...                                    | Blank lines |
|-----------------------------------------------|-------------|
| **Before** Scene Heading (from any element)   | 2           |
| Scene Heading and Action                      | 1           |
| Action paragraphs                             | 1           |
| Action and Character cue                      | 1           |
| Character cue and Dialogue                    | 0           |
| Character cue and Parenthetical               | 0           |
| Parenthetical and Dialogue                    | 0           |
| Dialogue lines (same character)               | 0           |
| Dialogue block and next Character cue         | 1           |
| Dialogue block and Action                     | 1           |
| Transition (before and after)                 | 1           |
| FADE IN: and first Scene Heading              | 1           |

> **Note:** Final Draft defaults to 2 blank lines before scene headings (triple-space). Some writers and software use 1 blank line (double-space). Both are seen in professional scripts, but 2 is the standard default.

**"Single-spaced"** in screenplay context means: no extra line between consecutive lines within the same element. A "blank line" is a single empty line (not double-spacing).

---

## 8. Page Break Rules

Page breaks follow strict rules to maintain readability:

### 8.1 Elements That Cannot End a Page

| Element                   | Rule                                                                   |
|---------------------------|------------------------------------------------------------------------|
| Scene Heading             | Never alone at page bottom (must have at least 1 line of action below) |
| Character Name (Cue)      | Never orphaned at page bottom — must have dialogue with it             |
| Parenthetical             | Never alone at page bottom (keep with character cue)                   |
| END OF ACT / END OF SCENE | Cannot immediately precede a page break                                |

**Exception:** An establishing shot scene heading (`EST. CITY SKYLINE - DAY`) can appear alone at the bottom because it IS the complete scene.

### 8.2 Elements That Cannot Start a Page

| Element    | Rule                                              |
|------------|---------------------------------------------------|
| Transition | Never at the top of a page (keep at bottom)       |

### 8.3 Action Breaks

- Minimum **2 lines** of action required before a page break.
- Break only at **sentence ends** (never mid-sentence).
- Ideally, at least 2 lines of action should appear after the break too.
- If splitting is impossible while meeting these requirements, move the entire action block to the next page.

### 8.4 Dialogue Breaks

- Minimum **2 lines** of dialogue required before a page break.
- Break only at **sentence ends**.
- Cannot break immediately after a parenthetical within dialogue.
- Use `(MORE)` at the bottom and `CHARACTER (CONT'D)` at the top (see Section 6.2).

### 8.5 Widow/Orphan Avoidance

- Avoid leaving a single word ("widow word") dangling on the last line of an action block.
- Avoid orphan lines (single line at the top of a new page separated from its paragraph).

---

## 9. Dialogue Group Structure

A **dialogue group** (or dialogue block) is the atomic unit of character speech:

```
[Character Cue]
[Parenthetical]  <- optional
[Dialogue]
[Parenthetical]  <- optional, mid-dialogue
[Dialogue]       <- continuation
```

**The group always starts with a Character Cue** and contains at least one Dialogue element. Parentheticals are optional and can appear before dialogue or between dialogue lines.

A **response block** (interactive/game-specific) may follow a dialogue group to present player choices. This is not part of standard screenplay format but is common in narrative design tools.

---

## 10. TV Script Formatting

TV scripts (teleplays) follow the same basic formatting as film screenplays with these key differences:

### 10.1 Single-Camera vs. Multi-Camera

| Feature              | Single-Camera (Drama/Prestige)         | Multi-Camera (Traditional Sitcom)        |
|----------------------|----------------------------------------|------------------------------------------|
| Formatting           | Same as film screenplay                | Distinct format (see below)              |
| Action text          | Normal case                            | ALL CAPS                                 |
| Line spacing         | Single-spaced                          | Double-spaced                            |
| Dialogue             | Normal case                            | Normal case                              |
| Scene headings       | Standard slug lines                    | May be underlined                        |
| Page count (30 min)  | ~25-35 pages                           | ~45-55 pages (double-spacing inflates)   |
| Page count (60 min)  | ~50-65 pages                           | N/A                                      |
| Character entrances  | Normal action                          | Underlined                               |
| Sound effects        | ALL CAPS in action                     | Underlined                               |
| Cast list per scene  | Not used                               | Listed after scene heading               |

### 10.2 Act Breaks

| Element           | Format                                                        |
|-------------------|---------------------------------------------------------------|
| Act Heading       | Centered, ALL CAPS, bold, underlined: `ACT ONE`               |
| End of Act        | Centered, ALL CAPS, bold, underlined: `END OF ACT ONE`        |
| Teaser/Cold Open  | Centered, ALL CAPS, bold, underlined: `TEASER` or `COLD OPEN` |
| Tag/Button        | Centered, ALL CAPS: `TAG`                                     |

**Rules:**
- Each act begins on a **new page**.
- If an act ends mid-page, leave the remaining space blank.
- Streaming scripts often omit explicit act breaks.

### 10.3 Typical TV Structures

**Hour-Long Drama (50-65 pages):**
- Teaser (2-5 pages)
- Act One through Act Four or Five (9-15 pages each)
- Optional Tag (1-2 pages)

**Half-Hour Comedy — Single-Cam (25-35 pages):**
- Cold Open (1-3 pages)
- Act One (~12-18 pages)
- Act Two (~10-15 pages)
- Optional Tag (1-2 pages)

**Half-Hour Comedy — Multi-Cam (45-55 pages):**
- Cold Open (2-5 pages)
- Act One (~18-22 pages)
- Act Two (~18-22 pages)
- Optional Tag (2-3 pages)

---

## 11. Character Name Conventions

| Convention       | Example                        | Meaning                                          |
|------------------|--------------------------------|--------------------------------------------------|
| First appearance | `JAIME (30s)`                  | Age hint in first action description, not in cue |
| Voice over       | `JAIME (V.O.)`                 | Character narrates but isn't in the scene        |
| Off screen       | `JAIME (O.S.)`                 | Character is present but not visible             |
| Off camera       | `JAIME (O.C.)`                 | Multi-camera TV convention for O.S.              |
| Continued        | `JAIME (CONT'D)`               | Same speaker after interruption                  |
| On the phone     | `JAIME (ON PHONE)` or filtered | Sometimes parenthetical, sometimes extension     |
| Subtitled        | `JAIME (SUBTITLED)`            | Dialogue in foreign language                     |
| Pre-lap          | `JAIME (PRE-LAP)`              | Audio starts before the visual cut               |

**Name matching rules for CONT'D:**
- Case-insensitive: `JAIME` = `jaime` = `Jaime`
- Extensions stripped: `JAIME (V.O.)` matches `JAIME`
- Only the base name matters for continuation detection

---

## 12. Revision Colors (Production)

During production, script revisions are printed on colored paper to track changes. Each revision round uses a different color.

### 12.1 Standard Color Sequence (WGA West)

| Revision #   | Color                                        |
|--------------|----------------------------------------------|
| Original     | White                                        |
| 1st          | Blue                                         |
| 2nd          | Pink                                         |
| 3rd          | Yellow                                       |
| 4th          | Green                                        |
| 5th          | Goldenrod                                    |
| 6th          | Buff                                         |
| 7th          | Salmon                                       |
| 8th          | Cherry                                       |
| 9th          | Tan                                          |
| 10th         | Ivory                                        |
| 11th+        | Double White, Double Blue... (cycle repeats) |

### 12.2 Revision Marks

- Changed lines are marked with an **asterisk** (`*`) in the right margin.
- Each revised page includes the **color name** and **revision date** in the header (e.g., `BLUE REVISION - 01/15/2026 - 56.`).
- The title page lists **all revision dates and colors** in chronological order.
- Full script revisions: entire script reprinted in the new color.
- Partial revisions: only changed pages are replaced (most common).

### 12.3 Regional Variations

- **UK productions** sometimes swap Blue and Pink (White, Pink, Blue, then Yellow, Green, Goldenrod...).
- Some TV shows use their own custom revision color sets.

---

## 13. Element Ordering on the Page

The typical order of elements as they appear on a screenplay page:

```
FADE IN:                                    <- Transition (opening only, left-aligned)

INT. LIVING ROOM - DAY                      <- Scene Heading

Action description paragraph.               <- Action

                      CHARACTER NAME         <- Character Cue
                 (parenthetical)             <- Parenthetical (optional)
            Dialogue text here.              <- Dialogue

                      ANOTHER CHARACTER      <- Character Cue
            Response dialogue.               <- Dialogue

More action description.                    <- Action

                      CHARACTER NAME (CONT'D) <- Character Cue (with continuation)
            Continued dialogue.              <- Dialogue

                                 CUT TO:     <- Transition (right-aligned)

INT. OFFICE - NIGHT                         <- Scene Heading (new scene)
```

**Visual flow pattern:** Scene Heading -> Action -> Character/Dialogue blocks -> (repeat) -> Transition -> next Scene Heading.

---

## 14. Script Opening & Closing

### 14.1 Opening

Every screenplay begins with:

```
FADE IN:

INT. FIRST LOCATION - DAY
```

- `FADE IN:` is the ONLY transition that is left-aligned (at the action margin, 1.5").
- Followed by 1 blank line, then the first scene heading.

### 14.2 Closing

Every screenplay ends with:

```
            ... final line of dialogue or action.

                                        FADE OUT.


                         THE END
```

- `FADE OUT.` — right-aligned, ALL CAPS, ends with a **period**.
- 2-3 blank lines after `FADE OUT.`
- `THE END` — centered, ALL CAPS, may be underlined.

---

## 15. Physical Presentation & Binding

| Property    | Standard                                                         |
|-------------|------------------------------------------------------------------|
| Printing    | Single-sided only                                                |
| Paper       | Standard 20 lb. white bond paper                                 |
| Binding     | Two brass brads (fasteners) through three-hole punched paper     |
| Brad holes  | Use the **top and bottom** holes; leave the middle hole **empty**|
| Cover       | Plain white or light pastel card stock                           |
| Back cover  | Same plain card stock                                            |

**Never use:** spiral binding, plastic binding, staples, ring binders, fancy covers, or decorative elements.

---

## 16. Common Mistakes

1. **Over-using transitions** — Modern screenplays rarely use `CUT TO:`. It's implied.
2. **Camera directions** — Avoid `CLOSE UP ON`, `PAN TO`, etc. in spec scripts. That's the director's job.
3. **Overly long action blocks** — Keep to 4-5 lines max. Use white space.
4. **ALL CAPS abuse** — Only for: scene headings, character cues, transitions, first character introduction, and important sounds/props.
5. **Parenthetical overuse** — If it's more than a few words, it should be an action line.
6. **Missing blank lines** — Always one blank line before scene headings, character cues, and transitions.
7. **Dialogue width** — Dialogue should be narrower than action. If it spans the full page width, the margins are wrong.
8. **Scene numbers in spec scripts** — Only shooting scripts use scene numbers.
9. **Bold/italic overuse** — Emphasis should be extremely rare. If you need emphasis to convey meaning, the writing needs revision.
10. **`FADE OUT.` with colon** — `FADE OUT.` ends with a period, not a colon. `FADE IN:` uses a colon.
11. **Widow words** — Never leave a single word dangling at the end of an action paragraph.

---

## Sources

- [Final Draft — How to Format a Screenplay](https://www.finaldraft.com/learn/how-to-format-a-screenplay/)
- [Final Draft — Screenplay Formatting Elements](https://www.finaldraft.com/learn/screenplay-formatting-elements/)
- [Final Draft — Standard Revision Set Colors](https://kb.finaldraft.com/hc/en-us/articles/15575314119316-What-are-the-standard-revision-set-colors)
- [Final Draft — How to Format Television Scripts](https://www.finaldraft.com/blog/how-to-format-television-scripts)
- [StudioBinder — Screenplay Margins Explained](https://www.studiobinder.com/blog/screenplay-margins/)
- [StudioBinder — CONT'D Meaning in Screenplay Formatting](https://www.studiobinder.com/blog/contd-meaning-screenplay-formatting/)
- [StudioBinder — Script Revision Colors Explained](https://www.studiobinder.com/blog/what-are-script-revision-colors/)
- [Story Sense — Screenplay Format Guide: Margins](https://www.storysense.com/format/margins.htm)
- [Story Sense — Screenplay Format Guide: Transitions](https://storysense.com/format/transitions.htm)
- [Scribophile — How to Format a Screenplay](https://www.scribophile.com/academy/how-to-format-a-screenplay)
- [John August — Introducing Courier Prime](https://johnaugust.com/2013/introducing-courier-prime)
- [Courier Prime — Google Fonts](https://fonts.google.com/specimen/Courier+Prime)
- [QuoteUnquote Apps — Standard Screenplay Format](https://blog.quoteunquoteapps.com/standard-screenplay-format-the-writers-guide/)
- [Fountain — Syntax Specification](https://fountain.io/syntax/)
- [Screenwriting.io — Standard Screenplay Format](https://screenwriting.io/what-is-standard-screenplay-format/)
- [Screenwriting.io — What Are MORE and CONT'D Used For](https://screenwriting.io/what-are-more-and-contd-used-for-in-screenplays/)
- [Arc Studio — Correctly Format Using Capitals, Italics & Underlines](https://www.arcstudiopro.com/blog/how-to-correctly-format-your-screenplay-using-capitals-italics-underlines)
- [SetHero — Script & Schedule Revision Colors](https://sethero.com/blog/film-script-schedule-revision-colors/)
- [Scriptation — Script Revision Colors for TV and Film](https://scriptation.com/blog/what-are-blue-pages_script-revision-colors/)
- [Celtx — Script Revision Colors](https://blog.celtx.com/understanding-script-revisions/)
- [Talentville — Screenplay Page Break Rules](https://www.talentville.com/snippet/screenplay-page-break-rules)
- [ScriptWritingSecrets — Page Break Rules](https://www.scriptwritingsecrets.com/PageBreak.htm)
- [ScriptWritingSecrets — Headers and Footers](https://www.scriptwritingsecrets.com/HeadersFooters.htm)
- [Screenplay.com — Basic Screenplay Format](https://screenplay.com/pages/basic-screenplay-format)
- [WGA Foundation — Formatting Your Spec Script](https://www.wgfoundation.org/blog/2022/5/2/formatting-your-spec-script-a-primer-part)
- [No Film School — When to Use MORE and CONT'D](https://nofilmschool.com/when-to-use-more-contd-in-screenplays)
- [ScreenCraft — Screenplay Format: 6 Elements You Have to Get Right](https://screencraft.org/blog/elements-of-screenplay-formatting/)
- [Story Sense — Screenplay Format Guide: Scene Headings](https://www.storysense.com/format/headings.htm)
- [Story Sense — Screenplay Format Guide: Dialogue](https://www.storysense.com/format/dialogue.htm)
- [Final Draft — Single-Camera vs Multi-Camera Differences](https://www.finaldraft.com/blog/differences-single-camera-multi-camera-tv-pilot-scripts)
