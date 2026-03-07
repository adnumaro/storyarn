%{
  title: "Tables",
  category_label: "World Building",
  order: 3,
  description: "Spreadsheet-like grids within sheets for inventories, matrices, and structured lists."
}
---

Tables are a special block type — a **spreadsheet grid** inside a sheet. Perfect for inventories, relationship matrices, skill trees, or shop inventories.

---

## Creating a table

Add a block, choose **Table**, then define your columns. Each column has a name and a type — text, number, boolean, or select. Add rows as needed.

---

## Cell-level variables

Every cell becomes a variable using extended notation:

```
{sheet_shortcut}.{table_name}.{row_id}.{column_name}
```

This means flows can check specific cells: *"Does Jaime have more than 0 healing potions?"* by referencing the quantity cell directly.

---

## Column types

Table columns support the same types as regular blocks — text for names and descriptions, number for quantities and scores, boolean for flags, and select for categories.
