# Project Health Audit: Storyarn

**Generated:** 2026-02-23
**Mode:** Full
**Auditors:** 5 parallel specialist agents (Architecture, Performance, Security, Test Health, Dependencies)

---

## Executive Summary

### Health Score: B (75/100)

| Category     | Score   | Status          |
|--------------|---------|-----------------|
| Architecture | 78/100  | Good            |
| Security     | 78/100  | Good            |
| Dependencies | 74/100  | Needs Attention |
| Test Quality | 72/100  | Needs Attention |
| Performance  | 72/100  | Needs Attention |

Storyarn demonstrates strong architectural foundations with an excellent facade pattern, consistent authorization, proper CSRF/CSP security, and well-organized code. The main areas needing attention are: N+1 query patterns in secondary code paths, absence of LiveView streams, facade violations in the Evaluator subsystem, zero tests for 10 shared utility modules, and a monolithic JS bundle.

---

## Critical Issues (Must Address)

### 1. Evaluator Subsystem Bypasses Flows Facade (Architecture)
The `Storyarn.Flows.Evaluator.*` namespace is accessed directly from 14+ web layer files. The Flows facade has zero delegations for Evaluator modules — the single largest facade violation.

### 2. XSS via `raw()` in PlayerSlide (Security)
`player_slide.ex` renders dialogue text using `Phoenix.HTML.raw()` without `HtmlSanitizer.sanitize_html/1` at the rendering point. While upstream sanitization exists, this is a fragile defense-in-depth gap.

### 3. ILIKE Injection in Localization Search (Security)
`text_crud.ex` and `glossary_crud.ex` pass user search input directly into ILIKE patterns without using `SearchHelpers.sanitize_like_query/1`.

### 4. Session Cookie Not Encrypted (Security)
The session cookie is signed but not encrypted — `encryption_salt` is not set in the endpoint configuration.

### 5. No LiveView Streams in Any Editor (Performance)
All editors store full entity lists in socket assigns. No `stream/3` or `temporary_assigns` usage in any editor LiveView. Every re-render diffs entire entity collections.

### 6. MapCrud.list_ancestors N+1 Loop (Performance)
Sequential `Repo.get(Map, parent_id)` calls in a recursive loop — up to 50 queries per map page load. The Sheets context already solves this with a recursive CTE.

### 7. Shared Utilities Have Zero Tests (Testing)
All 10 modules in `lib/storyarn/shared/` (NameNormalizer, TreeOperations, ShortcutHelpers, SoftDelete, Validations, etc.) have no dedicated tests despite being used by every context.

---

## Cross-Category Correlations

1. **Facade violations (Arch) + Missing tests (Test):** The Evaluator bypass means untested code paths are also architecturally unsound — fixing the facade would naturally create testable boundaries.

2. **N+1 patterns (Perf) + Missing indexes (Perf):** The MapCrud ancestor traversal compounds with missing `flow_nodes.deleted_at` index and JSONB expression indexes.

3. **Monolithic JS bundle (Perf) + Heavy deps (Deps):** 41 hooks eagerly imported means Rete.js (8 pkgs), Leaflet (3), Tiptap (6), and CodeMirror (5) load on every page regardless of editor type.

4. **ILIKE injection (Security) + Search helpers exist (Arch):** The `SearchHelpers.sanitize_like_query/1` utility exists and is used in most places — the localization modules simply missed it.

---

## Top Recommendations

### Immediate (This Sprint)

- [ ] **[Security/Low effort]** Add `HtmlSanitizer.sanitize_html/1` at rendering point in `player_slide.ex`
- [ ] **[Security/Low effort]** Add `SearchHelpers.sanitize_like_query/1` to localization `text_crud.ex` and `glossary_crud.ex`
- [ ] **[Security/Low effort]** Add `encryption_salt` to session cookie config in `endpoint.ex`
- [ ] **[Deps/Low effort]** Remove unused `leaflet-textpath` from `package.json`
- [ ] **[Deps/Low effort]** Tighten `postgrex` constraint from `">= 0.0.0"` to `"~> 0.22"`
- [ ] **[Deps/Low effort]** Run `mix deps.update phoenix phoenix_live_view bandit swoosh lucide_icons`

### Short-term (Next 2 Sprints)

- [ ] **[Perf/Medium effort]** Convert `MapCrud.list_ancestors` to recursive CTE (copy from `SheetQueries`)
- [ ] **[Perf/Low effort]** Add missing database indexes (flow_nodes.deleted_at, map_connections pin columns, JSONB expression indexes)
- [ ] **[Arch/Medium effort]** Add Evaluator delegations to `Storyarn.Flows` facade
- [ ] **[Arch/Medium effort]** Add missing Localization submodule delegations to facade
- [ ] **[Test/Low effort]** Create tests for all 10 shared utility modules
- [ ] **[Test/Low effort]** Enable `async: true` on 29 synchronous DataCase tests
- [ ] **[Perf/Medium effort]** Batch reorder operations (replace N individual UPDATEs with single bulk query)
- [ ] **[Deps/Low effort]** Upgrade `gettext` from `~> 0.26` to `~> 1.0`

### Long-term (Backlog)

- [ ] **[Perf/High effort]** Implement LiveView streams for node/block/connection lists
- [ ] **[Perf/Medium effort]** Apply `start_async` deferred loading to `MapLive.Show`
- [ ] **[Perf/Medium effort]** Implement JS code splitting with dynamic `import()`
- [ ] **[Arch/High effort]** Split oversized handler files (`element_handlers.ex` at 1,147 lines)
- [ ] **[Test/Medium effort]** Add tests for 12 untested LiveViews (settings, workspace, localization, player)
- [ ] **[Deps/Medium effort]** Plan `hammer` v6 to v7 migration
- [ ] **[Deps/Low effort]** Replace `html2canvas` with maintained `html2canvas-pro` fork

---

## Detailed Reports

| Report       | Path                                      |
|--------------|-------------------------------------------|
| Architecture | `.claude/audit/reports/arch-review.md`    |
| Performance  | `.claude/audit/reports/perf-audit.md`     |
| Security     | `.claude/audit/reports/security-audit.md` |
| Test Health  | `.claude/audit/reports/test-audit.md`     |
| Dependencies | `.claude/audit/reports/deps-audit.md`     |
