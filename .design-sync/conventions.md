# Storyarn — build conventions

Storyarn is a narrative design platform for games: dark-first UI, teal primary, frosted floating panels over canvas editors. This project ships the app's **real Vue 3 components compiled and exposed as React components** on `window.Storyarn_e287ac.*` — build with them, not with hand-rolled lookalikes.

## Setup — dark-first

Storyarn runs dark. Put `class="dark"` on `<html>` or `<body>` (preferred — dialogs, menus and sheets float at the body level and pick the theme from there; the components also propagate it to their own floating content). Without it you get the light palette — valid, but not what the product ships.

## Using the components

- Every component is on `window.Storyarn_e287ac`: `const { Button, ConfirmDialog } = window.Storyarn_e287ac;`
- **Callbacks receive the value itself, never a DOM event**: `onChange={setName}`, `onCheckedChange={setOn}`, `onOpenChange={setOpen}`.
- React children render into the component's slot; overlays take structured props (`Dialog`'s `footer`, `Popover`'s `content`, `DropdownMenu`'s `items`, `Select`'s `options`).
- Per-component API and a working example: `components/<group>/<Name>/<Name>.d.ts` and `<Name>.prompt.md`. Read them before using a component.
- **Never use browser dialogs** (`confirm()`/`alert()`): every confirmation is `ConfirmDialog` (`variant="destructive"` for deletes).
- Editor property panels use the `*Field` components (`TextField`, `SelectField`, `ToggleField`, `SliderField`…) — they carry the product's exact inspector styling.

## Styling your own layout glue

shadcn HSL tokens. Raw tokens hold bare HSL triplets — consume as `hsl(var(--token))` or with alpha `hsl(var(--token) / 0.5)`; plain resolved aliases exist as `var(--color-*)`:

| Token pair                                            | Use                                             |
| ----------------------------------------------------- | ----------------------------------------------- |
| `--background` / `--foreground`                       | Page ground and default text                    |
| `--card` / `--card-foreground`                        | Elevated cards, panels                          |
| `--surface`                                           | Frosted floating chrome ground                  |
| `--popover` / `--popover-foreground`                  | Menus, tooltips                                 |
| `--primary` / `--primary-foreground`                  | Teal brand actions (`174 60% 45%`, both themes) |
| `--secondary`, `--muted`, `--accent` (+`-foreground`) | Subdued fills, secondary text, hover/selected   |
| `--destructive` / `--destructive-foreground`          | Danger                                          |
| `--border`, `--input`, `--ring`                       | Borders, input borders, focus rings             |
| `--radius` (+ `--radius-sm/md/lg/xl`)                 | Radius scale, base 0.5rem                       |

`_ds_bundle.css` carries the Tailwind utilities **the components themselves use** — don't rely on arbitrary utility classes being present; style your own layout with inline styles + token vars.

## Chrome classes (real product CSS)

- `.surface-panel` — frosted-glass floating panel; Storyarn's signature chrome for toolbars/docks over canvases.
- `.toolbar-btn` / `.toolbar-input` — ghost toolbar button, compact borderless input.
- `.dock-btn` (+ `.dock-btn-active`), `.dock-item`, `.dock-tooltip` — floating bottom dock, 32px icon buttons.

## Fonts

UI text: system sans stack (already on `body`). **"Courier Prime"** (400/700 + italics, self-hosted) is reserved for screenplay-formatted content: `font-family: "Courier Prime", "Courier New", Courier, monospace`.

## Where the truth lives

`styles.css` (base + chrome; imports `tokens/colors.css`, `fonts/fonts.css`, `_ds_bundle.css`) and each `components/<group>/<Name>/` folder. The README's component index lists everything shipped.

## Idiomatic snippet

```jsx
const { Button, Badge, TextField, SaveIndicator } = window.Storyarn_e287ac;

<div style={{ background: "hsl(var(--background))", minHeight: "100%", padding: 24 }}>
  <div
    className="surface-panel"
    style={{ display: "flex", gap: 4, padding: 6, alignItems: "center", width: "fit-content" }}
  >
    <button className="toolbar-btn">Select</button>
    <SaveIndicator status="saved" />
  </div>
  <div
    style={{
      background: "hsl(var(--card))",
      border: "1px solid hsl(var(--border))",
      borderRadius: "var(--radius-lg)",
      padding: 16,
      marginTop: 16,
      maxWidth: 280,
    }}
  >
    <Badge variant="secondary">dialogue</Badge>
    <TextField label="Node label" value="mira_intro" onChange={() => {}} />
    <Button style={{ marginTop: 12 }}>Open</Button>
  </div>
</div>;
```
