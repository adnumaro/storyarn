# Storyarn — theme conventions

**Scope: styles/tokens only.** Storyarn's app is Vue 3, so this project ships no React component bundle. Build designs from generic components (shadcn-style parts fit naturally — the product uses shadcn-vue) styled with the tokens, chrome classes, and fonts below.

## Setup — dark-first

Storyarn runs dark. Put `class="dark"` on the design's root element to get the product look (deep blue-gray `220 20% 10%` background, teal primary). Without it you get the light palette — valid, but not what the product ships. All tokens flip automatically with the `dark` class.

## Styling idiom — shadcn HSL tokens

Raw tokens hold bare HSL channel triplets; consume them as `hsl(var(--token))` or with alpha `hsl(var(--token) / 0.5)`:

| Token pair                                   | Use                                                     |
| -------------------------------------------- | ------------------------------------------------------- |
| `--background` / `--foreground`              | Page ground and default text                            |
| `--card` / `--card-foreground`               | Elevated cards, panels                                  |
| `--surface`                                  | Frosted floating chrome ground (no foreground pair)     |
| `--popover` / `--popover-foreground`         | Menus, tooltips, dropdowns                              |
| `--primary` / `--primary-foreground`         | Teal brand actions (`174 60% 45%`, same in both themes) |
| `--secondary` / `--secondary-foreground`     | Secondary buttons, subdued fills                        |
| `--muted` / `--muted-foreground`             | Disabled fills, secondary text                          |
| `--accent` / `--accent-foreground`           | Hover fills, selected rows                              |
| `--destructive` / `--destructive-foreground` | Delete/danger actions                                   |
| `--border`, `--input`, `--ring`              | Borders, input borders, focus rings                     |
| `--radius` (+ `--radius-sm/md/lg/xl`)        | Radius scale, base 0.5rem                               |

Resolved plain-CSS aliases also exist for every color: `var(--color-primary)`, `var(--color-border)`, etc. — use these when you don't need alpha.

## Chrome classes (real product CSS)

- `.surface-panel` — frosted-glass floating panel (blurred `--surface` at 92%, 0.75rem radius). Storyarn's signature: toolbars, docks, and palettes float on this over canvas editors.
- `.toolbar-btn` — ghost toolbar button; `.toolbar-input` — compact borderless toolbar input.
- `.dock-btn` (+ `.dock-btn-active`), `.dock-item`, `.dock-tooltip` — floating bottom dock: 32px icon buttons, bounce-on-hover, delayed mega-tooltip.

## Fonts

UI text: system sans stack (already set on `body`). **"Courier Prime"** (400/700, italic; self-hosted here) is reserved for screenplay-formatted content — dialogue pages, script text. Use `font-family: "Courier Prime", "Courier New", Courier, monospace` for those surfaces only.

## Where the truth lives

Read `styles.css` (base + chrome classes) and its imports `tokens/colors.css` (all token values, light + dark) and `fonts/fonts.css` before styling.

## Idiomatic snippet

```html
<div class="dark" style="background: hsl(var(--background)); min-height: 100%; padding: 24px;">
  <div class="surface-panel" style="display: flex; gap: 4px; padding: 6px; width: fit-content;">
    <button class="toolbar-btn">Select</button>
    <button class="dock-btn dock-btn-active">+</button>
  </div>
  <div
    style="background: hsl(var(--card)); border: 1px solid hsl(var(--border)); border-radius: var(--radius-lg); padding: 16px; margin-top: 16px;"
  >
    <h3 style="color: hsl(var(--card-foreground)); font-weight: 600;">Flow node</h3>
    <p style="color: hsl(var(--muted-foreground)); font-size: 0.875rem;">
      Condition · checks hero.trust
    </p>
    <button
      style="background: hsl(var(--primary)); color: hsl(var(--primary-foreground)); border: none; border-radius: var(--radius-md); padding: 6px 12px; margin-top: 12px;"
    >
      Open
    </button>
  </div>
</div>
```
