# Security Audit Report - Storyarn

**Date:** 2026-02-23
**Auditor:** Claude Opus 4.6 (Automated Security Audit)
**Stack:** Elixir 1.15+ / Phoenix 1.8 / LiveView 1.1 / PostgreSQL
**Methodology:** OWASP Top 10, manual code review

---

## Overall Score: 78 / 100

**Justification:** The codebase demonstrates a strong security posture with consistent authorization patterns, proper password hashing, CSRF protection, CSP headers, rate limiting, and encrypted OAuth token storage. However, several medium-severity issues exist including unsanitized ILIKE inputs, XSS vectors through `raw()` without sanitization, missing session cookie encryption, an IDOR-susceptible node lookup function, and a missing multipart upload size limit.

---

## 1. CRITICAL Vulnerabilities

**None identified.** No critical vulnerabilities that would allow immediate system compromise were found.

---

## 2. HIGH-Risk Issues

### H1. XSS via `raw()` without `HtmlSanitizer` in PlayerSlide

**Files:**
- `lib/storyarn_web/live/flow_live/player/components/player_slide.ex` (lines 29, 47)

**Description:** The `player_slide.ex` component renders dialogue text and scene descriptions using `Phoenix.HTML.raw()` directly without passing through `HtmlSanitizer.sanitize_html/1`. While the `Slide` module does sanitize text before building the slide (lines 28, 95), this creates a fragile security boundary. If any future code path constructs slides without going through `Slide.build/4`, XSS is possible.

**Recommendation:** Apply `HtmlSanitizer.sanitize_html/1` at the rendering point in `player_slide.ex` (defense-in-depth).

---

### H2. Missing ILIKE Sanitization in Localization and Glossary Search

**Files:**
- `lib/storyarn/localization/text_crud.ex` (lines 245-253)
- `lib/storyarn/localization/glossary_crud.ex` (lines 87-95)

**Description:** Both modules pass user search input directly into ILIKE patterns without escaping `%`, `_`, or `\` characters. The project has `SearchHelpers.sanitize_like_query/1` specifically for this purpose, but it is not used here.

**Recommendation:** Use `SearchHelpers.sanitize_like_query/1` in both `maybe_search` functions.

---

### H3. IDOR Risk with `get_node_by_id!/1` (No Project Scoping)

**File:**
- `lib/storyarn/flows/node_crud.ex` (lines 57-59)

**Description:** The function `get_node_by_id!/1` retrieves a node by primary key without project or flow scoping. Called from `preview_component.ex` when following connections during preview. If a user crafts WebSocket messages with arbitrary node IDs, they could traverse nodes from other projects.

**Recommendation:** Add flow_id or project_id scoping, or validate at the call site. The scoped alternative `get_node!/2` already exists.

---

### H4. Session Cookie Not Encrypted

**File:**
- `lib/storyarn_web/endpoint.ex` (lines 6-15)

**Description:** The session cookie is signed but not encrypted. The `encryption_salt` option is not set, meaning cookie contents can be read by anyone with cookie access.

**Recommendation:** Add `encryption_salt` to the session options and add a corresponding `SESSION_ENCRYPTION_SALT` environment variable in `runtime.exs`.

---

## 3. MEDIUM-Risk Issues

### M1. Missing Multipart Upload Size Limit in Endpoint

**File:**
- `lib/storyarn_web/endpoint.ex` (lines 53-56)

**Description:** `Plug.Parsers` does not specify a `length` limit for multipart uploads. Plug defaults to 8MB.

**Recommendation:** Add explicit size limits: `{:multipart, length: 20_000_000}`.

---

### M2. OAuth State Parameter Not Explicitly Validated

**File:**
- `lib/storyarn_web/controllers/oauth_controller.ex`

**Description:** The controller relies entirely on Ueberauth for CSRF/state validation. Consider adding specific logging for OAuth CSRF failures.

---

### M3. Development Cloak Encryption Key in Version Control

**File:**
- `config/config.exs` (lines 129-138)

**Description:** A development Cloak key is hardcoded in `config.exs`. Correctly overridden in production via the `CLOAK_KEY` environment variable. Acceptable for development but should be noted.

---

### M4. Password Complexity Requirements Are Minimal

**File:**
- `lib/storyarn/accounts/user.ex` (lines 100-108)

**Description:** Password validation requires only length (12-72 chars). Commented-out complexity rules exist but are not enabled.

**Recommendation:** Enable at least one complexity requirement or implement breached password checking (NIST 800-63B).

---

## 4. LOW-Risk Issues

### L1. Variable Interpolation in Slides

**File:** `lib/storyarn_web/live/flow_live/player/slide.ex` (lines 176-183)

String variable values ARE properly escaped via `Phoenix.HTML.html_escape/1` (line 218-219). Low risk.

### L2. OAuth Error Messages Expose Provider Details

**File:** `lib/storyarn_web/controllers/oauth_controller.ex` (lines 37-48)

Raw provider error messages are displayed to users. Consider logging details and showing generic messages.

### L3. LiveDashboard in Development

**File:** `lib/storyarn_web/router.ex` (lines 47-61)

Properly scoped to dev-only. No authentication even in development, but acceptable.

---

## 5. Positive Security Findings

### Authentication (9/10)
- **Bcrypt** password hashing with timing-attack resistance via `no_user_verify/0`
- **Session tokens**: 32 bytes from `:crypto.strong_rand_bytes`, 14-day validity, 7-day reissue
- **Magic link tokens**: SHA-256 hashed in DB, 15-minute expiry, single-use
- **Session fixation protection** via `renew_session/2` with CSRF token deletion
- **Password fields** marked `virtual: true, redact: true`
- **Sudo mode** for sensitive operations (20-minute window)

### Authorization (9/10)
- **Every mutating `handle_event`** in Flow, Sheet, Map, and Screenplay LiveViews uses `with_authorization/3`
- Read-only events correctly skip authorization
- **All mounts** verify access via `Projects.get_project_by_slugs`
- **Role-based access** via `ProjectMembership.can?/2` and `WorkspaceMembership.can?/2`
- Catch-all unauthorized for unknown actions

### CSRF & Headers (9/10)
- `:protect_from_forgery` plug enabled
- **CSP** with `script-src 'self' 'sha256-...'`, `frame-ancestors 'self'`, `base-uri 'self'`, `form-action 'self'`
- **HSTS** enabled in production
- **Secure cookies**: `same_site: "Lax"`, `http_only: true`, `secure: true` in production

### Rate Limiting (9/10)
- Login: 5/min per IP, Magic links: 3/min per email, Registration: 3/min per IP, Invitations: 10/hr per user
- Redis backend for production, ETS for development

### Input Validation (7/10)
- Ecto parameterized queries used consistently (no raw SQL injection)
- `fragment()` calls use parameterized bindings throughout
- `SearchHelpers.sanitize_like_query/1` used in main search paths
- HTML sanitizer used in localization, preview, and slide builder
- **Missing**: ILIKE sanitization in localization modules (H2)

### Secrets Management (8/10)
- OAuth credentials from environment variables
- Cloak encryption for OAuth tokens at rest (AES-GCM)
- `.env` files gitignored
- Parameter filtering for passwords, secrets, tokens, API keys
- `redact: true` on sensitive schema fields

### Dependency Security
- `mix hex.audit`: No retired packages found

---

## 6. Recommendations Summary

| Priority   | Issue                                      | Fix Effort  |
|------------|--------------------------------------------|-------------|
| HIGH       | H1. XSS in PlayerSlide `raw()`             | Low         |
| HIGH       | H2. ILIKE injection in localization search | Low         |
| HIGH       | H3. IDOR in `get_node_by_id!/1`            | Medium      |
| HIGH       | H4. Session cookie not encrypted           | Low         |
| MEDIUM     | M1. No multipart upload size limit         | Low         |
| MEDIUM     | M2. OAuth state validation not explicit    | Low         |
| MEDIUM     | M3. Dev encryption key in VCS              | Low         |
| MEDIUM     | M4. Minimal password complexity            | Low         |
| LOW        | L1-L3. Various informational items         | Very Low    |
