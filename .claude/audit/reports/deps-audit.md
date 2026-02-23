# Dependency Audit Report

**Project:** Storyarn
**Date:** 2026-02-23
**Score: 74/100**

---

## Score Justification

| Category           | Score  | Weight   | Notes                                                                                        |
|--------------------|--------|----------|----------------------------------------------------------------------------------------------|
| Security           | 82/100 | 25%      | No retired packages, bcrypt up-to-date, Cloak encryption sound. hackney pinned to old major. |
| Freshness          | 68/100 | 25%      | 4 deps behind major versions, 8 with available patch/minor updates                           |
| Unused/Dead Code   | 72/100 | 15%      | 2 potentially unused JS deps, 1 Elixir dep with barely any usage                             |
| Compatibility      | 85/100 | 15%      | Phoenix/LiveView/Ecto matrix is sound. Elixir ~> 1.15 is appropriate.                        |
| Maintenance Health | 62/100 | 10%      | html2canvas unmaintained (4 years), leaflet-textpath dormant (5 years)                       |
| License Compliance | 90/100 | 10%      | All permissive licenses (MIT, Apache-2.0, ISC, BSD). No GPL.                                 |

---

## 1. Critical Issues

### 1.1 Unmaintained JS Dependencies

- **`html2canvas` (1.4.1)** -- Last published 4+ years ago. Used only in `assets/js/map_canvas/exporter.js` for PNG export. A maintained fork `html2canvas-pro` (v2.0.0) exists.

- **`leaflet-textpath` (1.3.0)** -- Last published 5+ years ago. **No imports found in any JS source file.** This is an unused dependency that should be removed.

### 1.2 Multiple HTTP Clients

The project ships three HTTP client stacks: `req` (via Finch/Mint), `hackney`, and `tesla` (transitive from oauth2). This is acceptable because `hackney` is required by `ex_aws` and `oauth2`/`tesla`, but it means increased binary size. Monitor for when upstream deps support `req` as an alternative backend.

---

## 2. Outdated Elixir Dependencies

### Major Version Behind (Constraint Blocks Update)

| Dependency             | Current   | Latest    | Constraint  | Action                                   |
|------------------------|-----------|-----------|-------------|------------------------------------------|
| `gettext`              | 0.26.2    | **1.0.2** | `~> 0.26`   | Update to `~> 1.0`. No breaking changes. |
| `hammer`               | 6.2.1     | **7.2.0** | `~> 6.2`    | Major rewrite. Plan migration.           |
| `hammer_backend_redis` | 6.2.0     | **7.1.0** | `~> 6.1`    | Must upgrade with hammer.                |
| `hackney`              | 1.25.0    | **3.2.0** | `~> 1.20`   | Blocked by upstream deps. No action now. |

### Minor/Patch Updates Available (Safe)

| Dependency                | Current  | Latest   |
|---------------------------|----------|----------|
| `phoenix`                 | 1.8.3    | 1.8.4    |
| `phoenix_live_view`       | 1.1.22   | 1.1.24   |
| `bandit`                  | 1.10.2   | 1.10.3   |
| `swoosh`                  | 1.21.0   | 1.22.0   |
| `image`                   | 0.62.1   | 0.63.0   |
| `lazy_html`               | 0.1.8    | 0.1.10   |
| `lucide_icons`            | 2.0.15   | 2.0.17   |
| `phoenix_test_playwright` | 0.10.0   | 0.12.1   |

---

## 3. Overly Loose Version Constraints

- **`postgrex`**: `">= 0.0.0"` -- accepts any version. Should be `"~> 0.22"` (in `mix.exs` line 62).
- **`lazy_html`**: `">= 0.1.0"` -- should be `"~> 0.1"` (in `mix.exs` line 66).

---

## 4. Unused/Questionable Dependencies

### Elixir

- **`html_sanitize_ex`** -- Only 1 call site: `HtmlSanitizeEx.strip_tags()` in `lib/storyarn_web/live/sheet_live/components/audio_tab.ex` line 399. The project already uses `Floki` extensively for HTML parsing. Consider replacing with `Floki.parse_fragment/1 |> Floki.text/1` and removing the dependency.

### JavaScript

- **`leaflet-textpath`** -- Declared in `assets/package.json` line 43 but zero imports found in any source file. Remove it.

---

## 5. Security Summary

| Check                                    | Result                                                         |
|------------------------------------------|----------------------------------------------------------------|
| `mix hex.audit` (retired packages)       | PASS -- No retired packages                                    |
| Password hashing (`bcrypt_elixir` 3.3.2) | PASS -- up-to-date                                             |
| Encryption at rest (`cloak` AES-GCM)     | PASS -- proper key management                                  |
| OAuth libraries (ueberauth + strategies) | PASS -- all current                                            |
| JS npm audit                             | NOT RUN -- recommend running `cd assets && npm audit` manually |
| Unmaintained JS deps                     | WARNING -- html2canvas (4yr), leaflet-textpath (5yr)           |

---

## 6. License Compliance

**No copyleft (GPL/LGPL/AGPL) dependencies detected.** All dependencies use permissive licenses (MIT, Apache-2.0, ISC, BSD-2-Clause, BSD-3-Clause), which are compatible with proprietary use.

---

## 7. JS Dependency Analysis

No duplicate functionality detected. Each major library serves a distinct purpose:
- Rich text: TipTap (6 packages)
- Code editing: CodeMirror (6 packages)
- Flow canvas: Rete.js (8 packages, including `elkjs` for auto-layout)
- Map canvas: Leaflet (3 packages)
- Icons: Lucide (tree-shakeable, good practice with individual imports)
- UI: daisyUI, @floating-ui/dom, vanilla-colorful, SortableJS

All dev dependencies (`@biomejs/biome`, `vitest`, `playwright`, `@lezer/*`, `jsdom`) are current.

---

## 8. Prioritized Recommendations

**Priority 1 -- Quick Wins (Do Now):**
1. Remove `leaflet-textpath` from `assets/package.json`
2. Run `mix deps.update phoenix phoenix_live_view bandit swoosh lazy_html lucide_icons`
3. Tighten `postgrex` constraint to `"~> 0.22"`
4. Tighten `lazy_html` constraint to `"~> 0.1"`

**Priority 2 -- Short Term:**
5. Upgrade `gettext` from `~> 0.26` to `~> 1.0` (no breaking changes)
6. Update `phoenix_test_playwright` to `~> 0.12`
7. Replace `html2canvas` with `html2canvas-pro`
8. Evaluate removing `html_sanitize_ex` (1 call site, replaceable with Floki)

**Priority 3 -- Medium Term:**
9. Plan `hammer` v6 to v7 migration
10. Monitor `hackney` 3.x adoption by upstream deps
11. Consider replacing `hackney` with `req` for ExAws (supported since ex_aws 2.6.0)

**Priority 4 -- Low Priority:**
12. Update `image` constraint to include `~> 0.63`
13. Audit daisyUI v5 class usage
