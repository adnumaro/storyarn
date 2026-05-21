# PostHog Analytics Integration Plan

**Status:** phase 1 implemented, error tracking comparison enabled behind env config
**Date drafted:** 2026-05-16
**Branch:** `feat/live-vue-sheets`
**Scope:** minimal pre-production product analytics for the public landing page,
authentication funnel, workspace/project activation, and core app actions.

## Context

Storyarn is not in production yet. This makes analytics most useful now, before
the first public traffic arrives. The initial integration should answer product
questions without turning analytics into a large implementation effort and
without leaking private narrative content.

Storyarn currently has:

- Sentry client initialization in `assets/js/utils/sentry.js`.
- Root metadata in `lib/storyarn_web/components/layouts/root.html.heex`.
- Runtime environment configuration in `config/runtime.exs`.
- A strict CSP in `lib/storyarn_web/router.ex`.
- A Phoenix + LiveView + LiveVue frontend entry point in `assets/js/app.js`.
- No existing product analytics abstraction.

Primary references:

- <https://posthog.com/docs/libraries/js>
- <https://hexdocs.pm/posthog/readme.html>
- <https://posthog.com/docs/product-analytics/group-analytics>

## Recommendation

Implement a minimal PostHog integration before production launch.

Do not implement the full analytics taxonomy, session replay, feature flags, or
group analytics before launch. Those should be staged after production once the
basic data pipeline is proven.

The pre-production target is:

- Pageviews for public and authenticated routes.
- Stable user identity after login/signup.
- A small set of activation events.
- A privacy allowlist that blocks private story content from event properties.
- A single Elixir facade so backend instrumentation stays consistent.

## Goals

- Preserve the first production visit/signup/activation data.
- Track the landing-to-signup-to-first-project funnel.
- Track basic product activation without capturing user-authored content.
- Use one stable event contract shared by frontend and backend.
- Keep PostHog optional in dev/test and disabled without config.
- Make future expansion incremental and low-risk.

## Non-Goals For The First Pass

- No session replay.
- No autocapture across the whole app.
- No Sentry removal. PostHog error tracking runs as a parallel opt-in signal so
  we can compare grouping, request context, frontend exception capture, and
  operational noise before choosing a primary error tool.
- No feature flags or experiments.
- No group analytics billing activation.
- No analytics events that include story text, descriptions, slugs, asset URLs,
  filenames, imported content, exported content, or user emails.
- No inline PostHog script snippet. Storyarn should use packaged JS through Vite.

## Architecture

### Backend

Use `Storyarn.Analytics` as the local privacy boundary and the official PostHog
Elixir SDK as the transport. Product events call `PostHog.capture/2` with an
explicit `distinct_id`, matching the official SDK contract. The local facade
keeps PostHog's request/error context separate from product analytics by
dispatching product events through a small sanitized payload.

Configure it through runtime env:

- `POSTHOG_ENABLED`
- `POSTHOG_PROJECT_API_KEY`
- `POSTHOG_HOST`
- `POSTHOG_ERROR_TRACKING_ENABLED`
- `POSTHOG_FRONTEND_ERROR_TRACKING_ENABLED`

Recommended defaults:

- dev disabled unless explicitly enabled; test uses `test_mode: true`
- prod enabled only when both `POSTHOG_ENABLED=true` and
  `POSTHOG_PROJECT_API_KEY` are present
- `POSTHOG_HOST=https://us.i.posthog.com` by default, or EU/self-hosted when
  selected in PostHog
- PostHog error tracking disabled unless `POSTHOG_ENABLED=true`, a project key
  is present, and `POSTHOG_ERROR_TRACKING_ENABLED` is not false
- frontend exception autocapture follows `POSTHOG_FRONTEND_ERROR_TRACKING_ENABLED`
- Sentry remains enabled independently through `SENTRY_DSN`
- PostHog test mode drops SDK events in test unless a test adapter is explicitly
  configured for local assertions

Create a small facade:

```txt
lib/storyarn/analytics.ex
lib/storyarn/analytics/posthog_adapter.ex
lib/storyarn/analytics/noop_adapter.ex
```

Public API:

```elixir
Storyarn.Analytics.track(scope_or_user, event_name, properties \\ %{})
Storyarn.Analytics.track_system(event_name, properties \\ %{})
Storyarn.Analytics.identify_user(user, properties \\ %{})
```

The facade should:

- derive `distinct_id` from `user.id`
- use no-op behavior when disabled
- sanitize properties through an event-specific allowlist
- reject unknown event names
- never raise from analytics code in request/LiveView paths
- log debug-level failures only when useful

### Error Tracking

PostHog error tracking is intentionally separate from product analytics:

- `PostHog.Integrations.Plug` captures request context for backend exceptions,
  similar to `Sentry.PlugContext`.
- authenticated HTTP and LiveView processes set `distinct_id = "user:<id>"` in
  PostHog context and `user_id` in Logger metadata.
- PostHog's Logger handler captures `:error` and crash logs when enabled.
- frontend error tracking captures unhandled browser errors and promise
  rejections, but not `console.error`.
- product analytics events do not inherit request URL/path/IP context.

Use PostHog and Sentry side by side during early production traffic. Compare:

- whether PostHog groups Phoenix/LiveView errors as usefully as Sentry
- whether stack traces and source context are sufficient
- whether request context is useful without being too noisy
- whether frontend errors are actionable enough without session replay

### Frontend

Install `posthog-js` via pnpm.

Use a local module:

```txt
assets/js/utils/posthog.js
```

Import it from `assets/js/app.js`.

Use package import, not the HTML snippet. Prefer the no-external module for the
first pass:

```ts
import "posthog-js/dist/exception-autocapture";
import posthog from "posthog-js/dist/module.no-external";
```

This keeps Storyarn aligned with the existing CSP and avoids remotely loaded
extensions. The exception autocapture extension is bundled explicitly so browser
error tracking works without enabling replay, surveys, or remote extension
loading.

Expose config through root meta tags:

```html
<meta name="posthog-key" content="..." />
<meta name="posthog-host" content="..." />
<meta name="posthog-enabled" content="true" />
<meta name="posthog-user-id" content="..." />
<meta name="posthog-user-locale" content="..." />
```

Do not expose email.

The frontend utility should provide:

```ts
initPostHog()
capture(eventName, properties?)
capturePageview()
identifyCurrentUser()
```

For LiveView navigation:

- capture initial `page viewed` after init
- listen to `phx:page-loading-stop`
- dedupe only exact same-path repeats, so navigation between two sheets still
  counts even though both send `route_family = "sheets"`
- do not send raw paths or URLs because project/workspace slugs may contain
  private user naming

PostHog JS adds URL/referrer properties automatically to captured events. The
frontend utility must strip those auto-properties in `before_send`, including
`$current_url`, `$pathname`, `$referrer`, `$initial_*`, `$session_entry_*`, and
`$prev_pageview_pathname`.

Disable browser capture when:

- no API key
- `posthog-enabled` is not true
- browser has opted out

### CSP

Add the configured PostHog host to `connect-src`.

For the minimal no-external first pass, script-src should not need external
PostHog hosts because PostHog is bundled by Vite. If we later enable replay,
surveys, toolbar, or external extensions, revisit CSP deliberately.

## Identity Contract

Use one user id across backend and frontend:

```txt
distinct_id = "user:<user_id>"
```

Allowed person properties:

- `locale`
- `created_at` if readily available and useful
- `is_super_admin`

Avoid:

- email
- name
- OAuth provider identity
- workspace/project names

If public anonymous users visit the landing page, PostHog can keep anonymous
ids. After signup/login, call `identify` with `user:<id>`.

## Privacy Contract

Analytics properties must be allowlisted by event type.

Allowed property categories:

- internal numeric ids: `workspace_id`, `project_id`, `sheet_id`, `flow_id`,
  `scene_id`
- coarse types: `entity_type`, `node_type`, `block_type`, `asset_type`,
  `export_format`, `import_format`
- coarse metrics: `count`, `duration_ms`, `size_bucket`, `status`,
  `error_category`
- booleans: `has_errors`, `was_duplicate`, `created_variant`, `is_first`

Forbidden property categories:

- project/workspace/sheet/flow/scene names
- slugs
- emails
- filenames
- asset URLs
- dialogue text
- screenplay text
- block values
- variable names
- localization source or translated text
- import/export payload content
- free-form error messages that may include user content

For errors, send stable categories:

```txt
validation_failed
permission_denied
not_found
rate_limited
storage_failed
unsupported_format
unknown
```

## Pre-Production Event Set

### Public and Auth Funnel

- `landing viewed`
- `landing cta clicked`
- `signup viewed`
- `login viewed`
- `user signed up`
- `user logged in`

Suggested properties:

- `source_route`
- `cta_id`
- `auth_method`

### Activation

- `workspace created`
- `project created`
- `first project opened`
- `sheet created`
- `flow created`
- `scene created`

Suggested properties:

- `workspace_id`
- `project_id`
- `is_first`

### Core Usage

- `asset uploaded`
- `asset variant created`
- `export generated`
- `import completed`
- `import failed`

Suggested properties:

- `project_id`
- `asset_type`
- `size_bucket`
- `purpose`
- `format`
- `status`
- `error_category`

### Navigation

- `page viewed`
- `project tool opened`

Suggested properties:

- `route_family`
- `tool`
- `workspace_id`
- `project_id`

## Deferred Event Set

Add after production launch:

- detailed sheet block events
- flow node and connection events
- scene pin/zone/layer events
- localization batch operations
- snapshot create/restore events
- usage limit hit/warning events
- onboarding milestones
- collaboration presence/lock events, only if they answer a specific question

## Group Analytics

Do not enable group analytics for the first pass.

Prepare naming so it can be added later:

```txt
workspace group key = "workspace:<id>"
project group key = "project:<id>"
```

PostHog group analytics is useful for B2B/project-level activation, but it is a
paid add-on and has a limited number of group types. Keep it as a second-stage
decision once we know which product metrics matter most.

## Implementation Phases

### Phase 1 - Configuration and Facades

1. Add the official PostHog Elixir SDK and route product events through
   `PostHog.capture/2`.
2. Add `posthog-js` dependency.
3. Add runtime config for PostHog.
4. Add root meta tags for frontend config and current user context.
5. Update CSP `connect-src`.
6. Create `Storyarn.Analytics` with no-op and PostHog adapters.
7. Create frontend `assets/js/utils/posthog.js`.
8. Wire frontend init into `assets/js/app.js`.

Verification:

- `mix deps.get`
- `pnpm install`
- `mix test`
- JS lint/format for touched files
- manual check that dev localhost sends events only when PostHog env is present
  and frontend metadata is rendered

### Phase 2 - Minimal Events

1. Track landing CTA and pageviews.
2. Track signup/login backend events.
3. Track workspace and project creation.
4. Track asset upload and variant creation.
5. Track export/import completion and failure.

Verification:

- unit tests for `Storyarn.Analytics` sanitization
- controller/context tests asserting analytics is called via a test adapter
- browser check that pageviews fire only when configured

### Phase 3 - Dashboard Setup

Create PostHog insights/funnels:

- landing viewed -> signup viewed -> user signed up
- user signed up -> workspace created -> project created
- project created -> first project opened
- project created -> first asset uploaded
- export generated by format
- import failed by format/error category

### Phase 4 - Expansion After Production

1. Add events around sheets/flows/scenes/localization.
2. Add usage-limit events.
3. Evaluate group analytics.
4. Evaluate session replay with strict masking and explicit triggers.
5. Evaluate feature flags only after the event pipeline is trusted.

## Testing Strategy

Backend:

- `NoopAdapter` never raises.
- `PostHogAdapter` maps events to PostHog `/capture/`.
- sanitizer drops forbidden keys.
- sanitizer keeps allowlisted keys.
- disabled config causes no capture.
- test adapter can assert event names/properties.

Frontend:

- init does nothing without meta config.
- init skips only when root PostHog metadata is absent.
- pageview dedupes repeated LiveView events by private pathname key, while only
  sending the normalized route family to PostHog.
- capture drops forbidden properties.
- identify uses user id only.

Integration:

- one smoke route with PostHog disabled
- one smoke route with fake config and mocked capture
- CSP includes configured PostHog host

## Open Questions

- US or EU PostHog cloud?
- Should anonymous landing page visitors be captured before cookie consent, or
  should tracking start only after consent?
- Do we want email-free `identify` immediately on signup, or use aliasing from
  anonymous id to user id?
- Should self-hosting be considered later, or is PostHog Cloud enough?
- Which five activation dashboards do we want before launch?

## Launch Checklist

- `POSTHOG_ENABLED=true`
- `POSTHOG_PROJECT_API_KEY` configured
- `POSTHOG_HOST` configured
- CSP connect-src includes host
- test mode enabled in test
- no session replay
- no autocapture
- no emails or user-authored content in event payloads
- first production dashboard created
- first production signup flow verified in PostHog
