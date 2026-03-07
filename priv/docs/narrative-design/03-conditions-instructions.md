%{
  title: "Conditions & Instructions",
  category_label: "Narrative Design",
  order: 3,
  description: "Branch your narrative with conditions and modify game state with instructions."
}
---

Conditions read your variables to make decisions. Instructions write to your variables to change game state. Together, they're how flows interact with your world data.

---

## Condition nodes

A condition node evaluates rules and routes to different outputs based on the result.

The **Condition Builder** is a visual interface — no code needed:

1. Pick a variable (e.g., `mc.jaime.health`)
2. Choose an operator (greater than, equals, contains...)
3. Set a value to compare against

---

## Logic groups

Combine rules with **All (AND)** or **Any (OR)**:

> *"Jaime has more than 50 health AND has the key"*
> → both must be true

> *"Player is a Mage OR has the spell scroll"*
> → either is enough

---

## Output pins

Simple conditions have **True / False** outputs. For switch-style logic, you can define custom cases — like checking a character's class with separate outputs for Warrior, Mage, and Rogue.

---

## Instruction nodes

Instructions **modify variables** when the flow passes through:

- **Set** — `mc.jaime.health = 75`
- **Add** — `mc.jaime.gold += 100`
- **Subtract** — `mc.jaime.health -= 25`
- **Toggle** — `quest.door.unlocked = !current`

A single instruction node can contain multiple assignments that execute in order.

---

## When to use inline vs. nodes

Dialogue responses support inline conditions and instructions for simple cases. Use dedicated nodes when the same condition is checked by multiple paths, the logic involves multiple rules, or several variables need to change together.
