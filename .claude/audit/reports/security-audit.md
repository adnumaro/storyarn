# Security Audit

## Score: 78/100

## Findings

### Critical (Must Fix)

**1. HTML Sanitizer allows javascript: URIs in href attributes**
File: `lib/storyarn_web/live/flow_live/helpers/html_sanitizer.ex:36-45`
Logic bug: `unsafe_attr?/2` first clause matches all string names and returns before checking the value for `javascript:`. The second clause is unreachable for string attribute names.
**OWASP:** A7:2017 - XSS
**Impact:** `<a href="javascript:alert(1)">` passes sanitization and renders via `raw()`.
**Fix:** Combine name and value checks in a single function clause.

**2. Missing authorization in LiveView component event handlers**
Locations:
- `sheet_live/components/sheet_title.ex:68,90` — `save_name`, `save_shortcut`
- `sheet_live/components/sheet_avatar.ex:78,99` — `remove_avatar`, `upload_avatar`
- `sheet_live/components/banner.ex:137,157` — `remove_banner`, `upload_banner`
- `map_live/handlers/undo_redo_handlers.ex:23` — `undo`, `redo`

These only check `can_edit` at UI level. A crafted WebSocket event bypasses the restriction.
**OWASP:** A1:2017 - Broken Access Control

**3. Unsanitized `raw()` in localization editor**
File: `lib/storyarn_web/live/localization_live/edit.ex:45`
`{raw(@text.source_text || "")}` renders dialogue text without sanitization.

### Warnings (Should Fix)

- No `force_ssl` in production configuration
- Session cookie missing `secure: true` flag
- No `filter_parameters` configuration for log scrubbing
- Hardcoded signing salts in `config.exs` (dev/test only, overridden in prod)
- `String.to_atom/1` with database-sourced input in `element_grouping.ex:183`
- `get_node_by_id!/1` fetches nodes without flow/project scoping

### Good Patterns

- **Authentication:** Bcrypt with timing-safe comparison, `redact: true` on passwords, Cloak AES-GCM for OAuth tokens, 14-day session expiry, 15-min magic link expiry, session fixation prevention
- **Authorization:** Well-designed `Authorize` helper, role-based ACL, consistent `with_authorization` usage in most handlers
- **SQL Injection:** Zero string interpolation in queries, all use `^` parameterization
- **CSRF:** `:protect_from_forgery` + `:put_secure_browser_headers` with custom CSP
- **XSS:** CSP with `script-src 'self'`, `frame-ancestors 'self'`, `textContent` usage in JS hooks
- **Rate Limiting:** Login (5/min), magic link (3/min), registration (3/min), invitations (10/hr), Redis backend in prod
- **Secrets:** All production secrets from env vars, Cloak vault for encryption at rest
- **File Uploads:** Content type allowlist, size limits, sanitized filenames
