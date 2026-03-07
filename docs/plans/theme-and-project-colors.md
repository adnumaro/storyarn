# Plan: Custom Theme + Per-Project Colors

## Part 1: Global Storyarn Theme

Replace daisyUI default `light`/`dark` themes with custom Storyarn palette.

### Colors (oklch)

| Role      | Light                          | Dark                           |
|-----------|--------------------------------|--------------------------------|
| Primary   | `oklch(78% 0.14 185)` (cyan)  | same                           |
| Secondary | `oklch(45% 0.04 260)` (slate) | same                           |
| Accent    | `oklch(72% 0.16 60)` (amber)  | same                           |
| Neutral   | `oklch(18% 0.025 260)` (dark steel) | same                      |

### Gradients (buttons only)

- `.btn-primary` → `linear-gradient(135deg, cyan → teal)`
- `.btn-secondary` → `linear-gradient(135deg, slate → dark slate)`, white text
- `.btn-accent` → `linear-gradient(135deg, amber → deep orange)`
- `.btn-neutral` → NO gradient (flat)

### Files to modify

**`assets/css/app.css`** — Replace the daisyui plugin config + add:
1. Custom theme variables under `:root, [data-theme="light"]` and `[data-theme="dark"]`
2. Gradient overrides for `.btn-primary`, `.btn-secondary`, `.btn-accent` (+ hover states)
3. Keep existing `--radius-field: 0.5rem` override

### Tasks

- [ ] 1.1 — Add custom color variables to `app.css` (override daisyUI defaults)
- [ ] 1.2 — Add gradient CSS for `.btn-primary`, `.btn-secondary`, `.btn-accent`
- [ ] 1.3 — Verify compilation and visual check

---

## Part 2: Per-Project Custom Colors

Allow each project to define its own primary + accent colors, applied inside `Layouts.focus`.

### Schema change

**`lib/storyarn/projects/project.ex`** — Already has `settings` (`:map`, default `%{}`).

Store colors inside `settings`:
```elixir
%{
  "theme" => %{
    "primary" => "#00D4CC",    # hex, user-picked
    "accent" => "#E8922F"      # hex, user-picked
  }
}
```

No migration needed — `settings` is already a JSONB column.

### Context change

**`lib/storyarn/projects/project.ex`** — Add helper:
```elixir
def theme_colors(%__MODULE__{settings: settings}) do
  case settings do
    %{"theme" => %{"primary" => p, "accent" => a}} -> %{primary: p, accent: a}
    _ -> nil
  end
end
```

### Layout injection

**`lib/storyarn_web/components/layouts.ex`** → `focus/1`:
- Read `@project.settings["theme"]`
- If present, render a `<style>` tag inside the layout that overrides `--color-primary` and `--color-accent` (convert hex → oklch in a helper, OR just use hex since CSS supports it in modern browsers)

Simplest approach — inject CSS variables directly:
```heex
<style :if={@project_theme}>
  :root {
    --color-primary: {@project_theme.primary};
    --color-accent: {@project_theme.accent};
  }
</style>
```

Since daisyUI v5 uses oklch, and users will pick colors via a color picker (which returns hex), we need a hex→oklch conversion. Options:
1. **JS-side**: Convert on save in the color picker hook, store as oklch string
2. **Elixir-side**: Convert hex→oklch on render (small utility function)
3. **CSS-side**: Use `color-mix()` or just use hex directly — modern browsers auto-convert

**Recommended: Store hex, convert to oklch in Elixir on render.** This keeps the stored format user-friendly and the rendered format daisyUI-compatible.

### Gradient update for project colors

The gradient CSS uses hardcoded oklch values. For project-scoped colors:
- Define CSS custom properties for gradient endpoints
- The gradient rules reference these properties
- Project override sets these properties

```css
/* Global defaults */
:root {
  --gradient-primary-from: oklch(78% 0.14 185);
  --gradient-primary-to: oklch(68% 0.12 210);
  --gradient-accent-from: oklch(75% 0.17 65);
  --gradient-accent-to: oklch(65% 0.18 40);
}

.btn-primary {
  background-image: linear-gradient(135deg, var(--gradient-primary-from), var(--gradient-primary-to));
}
```

Then project overrides set `--gradient-primary-from` / `--gradient-primary-to`.

### UI for picking project colors

**`lib/storyarn_web/live/project_live/settings.ex`** — Add a "Theme" section:
- Two `<.color_picker>` components (already exists in component registry)
- One for primary, one for accent
- Save to `project.settings.theme`
- "Reset to default" button to clear custom theme

### Files to modify

- [ ] 2.1 — `lib/storyarn/projects/project.ex` — Add `theme_colors/1` helper
- [ ] 2.2 — `lib/storyarn/shared/color_utils.ex` — New: hex→oklch conversion utility
- [ ] 2.3 — `lib/storyarn_web/components/layouts.ex` → `focus/1` — Inject project theme `<style>` tag
- [ ] 2.4 — `assets/css/app.css` — Use CSS custom properties for gradient endpoints
- [ ] 2.5 — `lib/storyarn_web/live/project_live/settings.ex` — Add Theme section with color pickers
- [ ] 2.6 — Wire save/reset events for project theme colors

---

## Execution order

1. **Part 1 first** (global theme) — this is independent and immediately visible
2. **Part 2 after** (per-project) — builds on Part 1's CSS variable structure

## Risks / Notes

- Hex→oklch conversion in Elixir: needs a small utility (no hex dep needed, just math on RGB→linear→oklch). Alternatively, use CSS `color()` function and let the browser convert.
- Focus outline / input focus rings also use `--color-primary` — project colors will automatically affect these too (desired behavior).
- The banner gradient on the workspace page also uses primary — that's global, NOT project-scoped (correct, since workspace view has no project context).
