%{
  title: "Dialogue Nodes",
  category_label: "Narrative Design",
  order: 2,
  description: "Character speech, player responses, and dialogue configuration."
}
---

Dialogue nodes are the most common node type. They represent **what a character says** and optionally **what the player can respond**.

---

## Writing dialogue

Select a dialogue node to open the side panel. You'll find:

- **Speaker** — link to a character sheet
- **Text** — the dialogue line (rich text with formatting)
- **Stage Directions** — optional acting notes
- **Menu Text** — shorter text for choice menus, if different from the full line

You can also attach audio for voiceover and set a technical ID for engine integration.

---

## Player responses

A dialogue node can have multiple **responses** — the choices a player makes. Each response gets its own text and output connection.

The order you define them is the order they appear in-game.

---

## Response conditions

Each response can have a **condition** that must be true for it to appear:

> *"[Strength > 15] Break down the door"*

If the player's strength is 15 or less, they never see this option.

---

## Response instructions

Each response can also modify variables when chosen:

> Player picks "Accept the quest" → `quest.tavern.accepted = true`

This keeps simple logic close to the dialogue without needing separate nodes.

---

## Speaker assignment

Linking a dialogue node to a character sheet shows the character's name and avatar on the node, enables localization extraction with speaker context, and helps you track which characters appear in which flows.
