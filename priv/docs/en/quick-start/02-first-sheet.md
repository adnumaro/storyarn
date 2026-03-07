%{
  title: "Your First Sheet",
  category_label: "Quick Start",
  order: 2,
  description: "Create a character sheet and understand how variables work."
}
---

In this guide you'll create a character sheet and see how its fields become variables that your flows can use.

---

## Create the sheet

Open your project, click **Sheets** in the toolbar, then **+ New Sheet**.

Name it "Jaime" and set the shortcut to `mc.jaime`. The shortcut is how other parts of your project reference this sheet.

---

## Add a number block

Click **+ Add Block**, choose **Number**, and label it "Health". Set the default value to `100`.

This creates the variable `mc.jaime.health` — usable in any flow.

---

## Add a select block

Add another block, choose **Select**, and label it "Class". Add three options: Warrior, Mage, Rogue. Set the default to Warrior.

This creates `mc.jaime.class`.

---

## Add a constant

Add a **Text** block, label it "Display Name", and set the value to "Sir Jaime of Brighthollow". Check **Is Constant**.

Constants are display-only. They don't become variables — use them for labels, descriptions, or any data that flows don't need to read.

---

## How variables work

Every non-constant block becomes a variable with the format `{sheet_shortcut}.{variable_name}`:

- Health → `mc.jaime.health` (number)
- Class → `mc.jaime.class` (select)
- Display Name → *(constant, not a variable)*

In the next guide, you'll use `mc.jaime.health` to create branching dialogue.
