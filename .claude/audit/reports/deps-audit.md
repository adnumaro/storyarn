# Dependency Audit

## Score: 72/100

> Note: `mix hex.audit`, `mix hex.outdated`, and `npm audit` could not be executed. Run manually for complete vulnerability assessment.

## Inventory

- **Elixir deps (direct):** 35 (27 prod, 8 dev/test)
- **Elixir deps (total in lock):** 59
- **JS deps (direct):** 27 (22 prod, 5 dev)

## Findings

### Critical (Vulnerabilities)

- Unable to run `mix hex.audit` or `npm audit` — manual execution required
- `hackney ~> 1.20` — Erlang HTTP client with history of CVEs. Only needed as `ex_aws` backend. Consider migrating to `Req`/`Finch`.
- `html_sanitize_ex ~> 1.4` — depends on `mochiweb`, no release since 2021

### Warnings (Outdated/Unused)

**Unused JS packages:**
- `leaflet-textpath ^1.3.0` — zero imports found
- `rete-render-utils ^2.0.2` — zero imports found

**Misplaced:**
- `@lezer/lr` — in devDependencies but imported at runtime by generated parser

**Version pinning concerns:**
- `postgrex ">= 0.0.0"` — open constraint, should be `~> 0.22`
- `lazy_html ">= 0.1.0"` — same, should be `~> 0.1`

**Potentially outdated:**
- `hammer 6.2.1` — 7.x available
- `html2canvas ^1.4.1` (JS) — abandoned since 2022

### Good Patterns

- Excellent dev/test isolation: `credo`, `sobelow`, `dialyxir`, `mix_unused` all `runtime: false`
- Test deps properly scoped: `ex_machina`, `mox`, `faker`, `phoenix_test`
- Cloak + cloak_ecto for encryption at rest
- Clean dual-backend rate limiting (ETS dev, Redis prod)
- Modern JS tooling: Biome, Vitest, Playwright
- Consistent Rete.js, Tiptap, CodeMirror ecosystems (all `^2.x`, `^3.x`, `^6.x`)
- No license conflicts detected (all MIT/Apache 2.0/BSD)
- No compile-time vs runtime misconfigurations
