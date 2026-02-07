# Phase 9: Production Polish

> **Goal:** Prepare Storyarn for production deployment with performance optimization, monitoring, and operational readiness
>
> **Priority:** Required before public launch
>
> **Dependencies:** All previous phases complete
>
> **Last Updated:** February 2, 2026

## Overview

This phase ensures Storyarn is ready for production use:
- Performance profiling and optimization
- Error monitoring and logging (Sentry, AppSignal)
- Production deployment (fly.io)
- Database optimization and scaling
- Security hardening
- Operational runbooks
- UX refinements based on testing
- Documentation for users and developers

**Design Philosophy:** Production readiness is not an afterthought. Observability, performance, and reliability are first-class concerns.

---

## Performance Optimization

### 9.1 Backend Performance

#### 9.1.1 Database Optimization

**Index Analysis:**
- [ ] Run `EXPLAIN ANALYZE` on critical queries
- [ ] Add missing indexes for common access patterns
- [ ] Review and optimize N+1 queries
- [ ] Add composite indexes for filtered queries

**Critical Queries to Optimize:**
```sql
-- Page tree loading (hierarchical query)
SELECT * FROM pages WHERE project_id = ? AND parent_id IS NULL ORDER BY position;

-- Flow with all nodes and connections (heavy query)
SELECT * FROM flows
JOIN flow_nodes ON flow_nodes.flow_id = flows.id
JOIN flow_connections ON flow_connections.flow_id = flows.id
WHERE flows.id = ?;

-- Localization strings for a language
SELECT * FROM localized_texts
WHERE project_id = ? AND locale_code = ?
ORDER BY source_type, status;

-- Backlinks query
SELECT * FROM entity_references WHERE target_type = ? AND target_id = ?;
```

**Recommended Indexes:**
```elixir
# Pages tree traversal
create index(:pages, [:project_id, :parent_id, :position])
create index(:pages, [:project_id, :shortcut]) # Already exists

# Flows with nodes
create index(:flow_nodes, [:flow_id, :type])
create index(:flow_connections, [:flow_id, :source_node_id])

# Localization queries
create index(:localized_texts, [:project_id, :locale_code, :status])
create index(:localized_texts, [:character_id, :locale_code])

# Asset lookups
create index(:assets, [:project_id, :content_type])
```

#### 9.1.2 Query Optimization

- [ ] Use `Repo.preload` strategically (avoid over-preloading)
- [ ] Implement pagination for large lists
- [ ] Add database query timeouts
- [ ] Use `Repo.stream` for large exports
- [ ] Implement cursor-based pagination for infinite scroll

**Preload Strategy:**
```elixir
# Bad: Over-preloading
Repo.get!(Flow, id) |> Repo.preload([:nodes, :connections, project: :workspace])

# Good: Load what you need
Repo.get!(Flow, id) |> Repo.preload([:nodes, :connections])
# Load project separately if needed
```

#### 9.1.3 Caching Strategy

**ETS Cache for:**
- [ ] User sessions (already using Phoenix token)
- [ ] Rate limiting counters (already implemented)
- [ ] Frequently accessed project settings

**Redis Cache for:**
- [ ] Collaboration presence (already using)
- [ ] Export job status
- [ ] API rate limiting

**Application-level Cache:**
```elixir
# lib/storyarn/cache.ex
defmodule Storyarn.Cache do
  use Nebulex.Cache,
    otp_app: :storyarn,
    adapter: Nebulex.Adapters.Local  # or Redis for distributed

  # Cache project settings for 5 minutes
  def get_project_settings(project_id) do
    get_or_store({:project_settings, project_id}, ttl: :timer.minutes(5)) do
      Projects.get_settings(project_id)
    end
  end
end
```

#### 9.1.4 Background Jobs

**Oban Configuration:**
```elixir
# config/config.exs
config :storyarn, Oban,
  repo: Storyarn.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days
    Oban.Plugins.Stager,
    {Oban.Plugins.Cron, crontab: [
      {"0 3 * * *", Storyarn.Workers.CleanupWorker},      # Daily cleanup
      {"*/5 * * * *", Storyarn.Workers.HealthCheckWorker} # Every 5 min
    ]}
  ],
  queues: [
    default: 10,
    exports: 5,
    imports: 3,
    emails: 10,
    cleanup: 2
  ]
```

**Background Jobs to Implement:**
- [ ] `ExportWorker` - Async project exports
- [ ] `ImportWorker` - Async project imports
- [ ] `AssetProcessingWorker` - Image thumbnails, optimization
- [ ] `CleanupWorker` - Delete old versions, expired tokens
- [ ] `TranslationWorker` - DeepL API calls (rate limited)

---

### 9.2 Frontend Performance

#### 9.2.1 LiveView Optimization

- [ ] Use `phx-update="stream"` for large lists (flows, pages, nodes)
- [ ] Implement virtual scrolling for localization view
- [ ] Debounce frequent events (typing, dragging)
- [ ] Use `phx-debounce` on inputs
- [ ] Minimize socket payload size

**Stream Usage:**
```elixir
# In mount
socket = socket
|> stream(:pages, Pages.list_pages(project))
|> stream(:flows, Flows.list_flows(project))

# In template
<div id="pages" phx-update="stream">
  <div :for={{dom_id, page} <- @streams.pages} id={dom_id}>
    <%= page.name %>
  </div>
</div>
```

#### 9.2.2 JavaScript Optimization

- [ ] Lazy load Rete.js (only on flow editor pages)
- [ ] Lazy load TipTap (only when editing)
- [ ] Minimize bundle size (tree shaking)
- [ ] Use dynamic imports for large modules

**Dynamic Import Pattern:**
```javascript
// Lazy load Rete.js
async function initFlowEditor(element) {
  const { createEditor } = await import('./flow_canvas/editor.js');
  return createEditor(element);
}
```

#### 9.2.3 Asset Optimization

- [ ] Enable gzip/brotli compression
- [ ] Configure aggressive caching for static assets
- [ ] Use CDN for static assets (optional)
- [ ] Optimize images on upload (already using libvips)

**Phoenix Static Configuration:**
```elixir
# endpoint.ex
plug Plug.Static,
  at: "/",
  from: :storyarn,
  gzip: true,
  cache_control_for_etags: "public, max-age=31536000",
  only: ~w(assets fonts images favicon.ico robots.txt)
```

---

## Monitoring & Observability

### 9.3 Error Tracking (Sentry)

#### 9.3.1 Sentry Setup

```elixir
# mix.exs
{:sentry, "~> 10.0"}

# config/runtime.exs
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  integrations: [
    oban: [
      capture_errors: true
    ]
  ]
```

#### 9.3.2 Error Context

```elixir
# Add user context to errors
def set_sentry_context(conn, user) do
  Sentry.Context.set_user_context(%{
    id: user.id,
    email: user.email,
    workspace_id: conn.assigns[:current_workspace]&.id
  })
end

# Add custom tags
Sentry.Context.set_tags_context(%{
  project_id: project.id,
  flow_id: flow.id
})
```

#### 9.3.3 Custom Error Grouping

```elixir
# Group similar errors together
config :sentry,
  before_send: {Storyarn.SentryFilter, :filter}

defmodule Storyarn.SentryFilter do
  def filter(event) do
    # Filter out expected errors
    case event.original_exception do
      %Ecto.NoResultsError{} -> nil  # Don't report 404s
      %Phoenix.Router.NoRouteError{} -> nil
      _ -> event
    end
  end
end
```

---

### 9.4 Application Monitoring (AppSignal or similar)

#### 9.4.1 Metrics to Track

**Business Metrics:**
- Active users (DAU, WAU, MAU)
- Projects created per day
- Flows edited per day
- Export/import operations
- Collaboration sessions

**Technical Metrics:**
- Request latency (p50, p95, p99)
- Database query time
- WebSocket message rate
- Background job throughput
- Error rate

#### 9.4.2 Custom Instrumentation

```elixir
# Using :telemetry
defmodule Storyarn.Telemetry do
  def execute_export(project_id, format) do
    :telemetry.span(
      [:storyarn, :export],
      %{project_id: project_id, format: format},
      fn ->
        result = Exports.export_project(project_id, format)
        {result, %{}}
      end
    )
  end
end

# Custom metrics
:telemetry.execute(
  [:storyarn, :collaboration, :user_joined],
  %{count: 1},
  %{project_id: project_id, user_id: user_id}
)
```

#### 9.4.3 Dashboard Setup

**Key Dashboards:**
1. **Overview** - Request rate, error rate, latency
2. **Database** - Query time, pool usage, slow queries
3. **WebSockets** - Connected users, message rate
4. **Background Jobs** - Queue depth, execution time, failures
5. **Business** - User activity, feature usage

---

### 9.5 Logging

#### 9.5.1 Structured Logging

```elixir
# config/config.exs
config :logger, :console,
  format: {Storyarn.LogFormatter, :format},
  metadata: [:request_id, :user_id, :project_id]

# lib/storyarn/log_formatter.ex
defmodule Storyarn.LogFormatter do
  def format(level, message, timestamp, metadata) do
    Jason.encode!(%{
      timestamp: format_timestamp(timestamp),
      level: level,
      message: message,
      metadata: Map.new(metadata)
    }) <> "\n"
  end
end
```

#### 9.5.2 Log Levels

| Level      | Usage                                            |
|------------|--------------------------------------------------|
| `:debug`   | Detailed debugging (disabled in prod)            |
| `:info`    | Normal operations (user actions, job completion) |
| `:warning` | Unexpected but handled situations                |
| `:error`   | Errors that need attention                       |

#### 9.5.3 Audit Logging

```elixir
# Track sensitive operations
defmodule Storyarn.AuditLog do
  def log_action(user, action, entity, metadata \\ %{}) do
    %AuditEntry{
      user_id: user.id,
      action: action,
      entity_type: entity.__struct__ |> to_string(),
      entity_id: entity.id,
      metadata: metadata,
      ip_address: metadata[:ip_address],
      inserted_at: DateTime.utc_now()
    }
    |> Repo.insert()
  end
end

# Usage
AuditLog.log_action(user, :delete_project, project, %{project_name: project.name})
```

---

## Security Hardening

### 9.6 Security Checklist

#### 9.6.1 Authentication & Authorization

- [ ] Review all permission checks (use `Authorize` helper consistently)
- [ ] Ensure CSRF protection on all forms
- [ ] Rate limiting on all auth endpoints (already implemented)
- [ ] Secure password requirements (already implemented)
- [ ] Session timeout for inactive users
- [ ] Sudo mode for sensitive operations (already implemented)

#### 9.6.2 Data Protection

- [ ] Encrypt sensitive data at rest (OAuth tokens already encrypted with Cloak)
- [ ] Validate all file uploads (type, size, content)
- [ ] Sanitize HTML output (TipTap content)
- [ ] SQL injection protection (Ecto parameterized queries)
- [ ] XSS protection (Phoenix HTML escaping)

#### 9.6.3 Network Security

- [ ] Force HTTPS in production
- [ ] Set security headers (CSP, HSTS, X-Frame-Options)
- [ ] Configure CORS properly
- [ ] Review WebSocket authentication

**Security Headers:**
```elixir
# lib/storyarn_web/plugs/security_headers.ex
defmodule StoryarnWeb.Plugs.SecurityHeaders do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-frame-options", "SAMEORIGIN")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "geolocation=(), microphone=()")
  end
end
```

#### 9.6.4 Security Scanning

- [ ] Run Sobelow regularly (`mix sobelow`)
- [ ] Dependency vulnerability scanning (`mix deps.audit`)
- [ ] Review security advisories for dependencies

---

## Production Deployment

### 9.7 Fly.io Deployment

#### 9.7.1 Fly.io Configuration

```toml
# fly.toml
app = "storyarn"
primary_region = "mad"  # Madrid

[build]
  dockerfile = "Dockerfile"

[env]
  PHX_HOST = "storyarn.fly.dev"
  PORT = "8080"
  POOL_SIZE = "10"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 1000
    soft_limit = 800

[[services]]
  protocol = "tcp"
  internal_port = 8080

  [[services.ports]]
    port = 80
    handlers = ["http"]

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/health"
    protocol = "http"
    timeout = 2000

[[vm]]
  cpu_kind = "shared"
  cpus = 2
  memory_mb = 1024
```

#### 9.7.2 Dockerfile (Release)

```dockerfile
# Dockerfile
ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.2
ARG DEBIAN_VERSION=bookworm-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js for assets
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY ../../mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY ../../config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Build assets
COPY ../../assets assets
RUN cd assets && npm ci && cd ..
RUN mix assets.deploy

# Compile the release
COPY ../../lib lib
COPY ../../priv priv
RUN mix compile

# Copy runtime config
COPY ../../config/runtime.exs config/
COPY rel rel
RUN mix release

# Start a new build stage for the minimal runtime image
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy the release from the builder stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/storyarn ./

USER nobody

CMD ["/app/bin/server"]
```

#### 9.7.3 Database (Fly Postgres)

```bash
# Create Postgres cluster
fly postgres create --name storyarn-db --region mad

# Attach to app
fly postgres attach storyarn-db --app storyarn

# Run migrations (via release command)
fly ssh console -C "/app/bin/storyarn eval 'Storyarn.Release.migrate()'"
```

#### 9.7.4 Redis (Fly Redis or Upstash)

```bash
# Option 1: Fly Redis
fly redis create --name storyarn-redis --region mad

# Option 2: Use Upstash (managed Redis)
# Set REDIS_URL in secrets
fly secrets set REDIS_URL="redis://..."
```

#### 9.7.5 Secrets Management

```bash
# Set production secrets
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly secrets set DATABASE_URL="postgres://..."
fly secrets set REDIS_URL="redis://..."
fly secrets set CLOAK_KEY="$(mix cloak.gen.key)"
fly secrets set GITHUB_CLIENT_ID="..."
fly secrets set GITHUB_CLIENT_SECRET="..."
fly secrets set GOOGLE_CLIENT_ID="..."
fly secrets set GOOGLE_CLIENT_SECRET="..."
fly secrets set DISCORD_CLIENT_ID="..."
fly secrets set DISCORD_CLIENT_SECRET="..."
fly secrets set RESEND_API_KEY="..."
fly secrets set SENTRY_DSN="..."
fly secrets set R2_ACCESS_KEY_ID="..."
fly secrets set R2_SECRET_ACCESS_KEY="..."
fly secrets set R2_BUCKET="..."
fly secrets set R2_ENDPOINT="..."
```

---

### 9.8 Health Checks

#### 9.8.1 Health Endpoint

```elixir
# lib/storyarn_web/controllers/health_controller.ex
defmodule StoryarnWeb.HealthController do
  use StoryarnWeb, :controller

  def index(conn, _params) do
    checks = %{
      database: check_database(),
      redis: check_redis(),
      storage: check_storage()
    }

    status = if Enum.all?(checks, fn {_, v} -> v == :ok end), do: :ok, else: :error

    conn
    |> put_status(if status == :ok, do: 200, else: 503)
    |> json(%{
      status: status,
      checks: checks,
      version: Application.spec(:storyarn, :vsn) |> to_string()
    })
  end

  defp check_database do
    case Storyarn.Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp check_redis do
    case Storyarn.Redis.command(["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  end

  defp check_storage do
    # Verify R2/S3 connection
    case Storyarn.Assets.Storage.health_check() do
      :ok -> :ok
      _ -> :error
    end
  end
end
```

#### 9.8.2 Readiness vs Liveness

```elixir
# /health - Full health check (readiness)
# /health/live - Simple liveness (just returns 200)

def live(conn, _params) do
  json(conn, %{status: :ok})
end
```

---

## Operational Runbooks

### 9.9 Runbooks

#### 9.9.1 Common Operations

**Deploy New Version:**
```bash
# Deploy from main branch
fly deploy

# Deploy specific version
fly deploy --image registry.fly.io/storyarn:v1.2.3

# Rollback to previous version
fly releases list
fly deploy --image registry.fly.io/storyarn:v1.2.2
```

**Run Migrations:**
```bash
fly ssh console -C "/app/bin/storyarn eval 'Storyarn.Release.migrate()'"
```

**Scale Application:**
```bash
# Scale to 3 instances
fly scale count 3

# Scale memory
fly scale memory 2048
```

**View Logs:**
```bash
fly logs
fly logs --app storyarn-db  # Database logs
```

**Database Backup:**
```bash
# Fly Postgres automatic backups
fly postgres backup list --app storyarn-db

# Manual backup
fly postgres backup create --app storyarn-db
```

#### 9.9.2 Incident Response

**High Error Rate:**
1. Check Sentry for error details
2. Check application logs: `fly logs`
3. Check database connectivity
4. Check Redis connectivity
5. Scale up if needed: `fly scale count 3`
6. Rollback if recent deploy: `fly deploy --image <previous>`

**Database Issues:**
1. Check Postgres logs: `fly logs --app storyarn-db`
2. Check connection pool: `fly ssh console -C "/app/bin/storyarn eval 'Storyarn.Repo.query(\"SELECT count(*) FROM pg_stat_activity\")' "`
3. Check slow queries in monitoring
4. Restart if needed: `fly postgres restart --app storyarn-db`

**Memory Issues:**
1. Check memory usage: `fly status`
2. Check for memory leaks in monitoring
3. Restart instances: `fly apps restart`
4. Scale memory if persistent: `fly scale memory 2048`

---

## UX Refinements

### 9.10 UX Polish

#### 9.10.1 Loading States

- [ ] Add skeleton loaders for page/flow lists
- [ ] Add progress indicators for exports/imports
- [ ] Improve initial load experience (optimistic UI)

#### 9.10.2 Error Handling

- [ ] User-friendly error messages (not technical)
- [ ] Retry buttons for transient failures
- [ ] Offline indicator with reconnection

#### 9.10.3 Accessibility

- [ ] Keyboard navigation throughout
- [ ] Screen reader support (ARIA labels)
- [ ] Color contrast compliance (WCAG AA)
- [ ] Focus management in modals

#### 9.10.4 Mobile Responsiveness

- [ ] Responsive sidebar (collapsible on mobile)
- [ ] Touch-friendly interactions
- [ ] Viewport-aware layouts

---

## Documentation

### 9.11 User Documentation

- [ ] Getting started guide
- [ ] Feature documentation (pages, flows, etc.)
- [ ] Keyboard shortcuts reference
- [ ] Export format documentation
- [ ] FAQ

### 9.12 Developer Documentation

- [ ] Architecture overview
- [ ] API documentation (if public API)
- [ ] Deployment guide
- [ ] Contributing guidelines
- [ ] Code style guide

---

## Implementation Order

| Order   | Task                        | Priority   | Testable Outcome        |
|---------|-----------------------------|------------|-------------------------|
| 1       | Database index optimization | High       | Faster queries          |
| 2       | Sentry integration          | High       | Errors tracked          |
| 3       | Structured logging          | High       | Logs queryable          |
| 4       | Health endpoints            | High       | Health checks pass      |
| 5       | Security headers            | High       | Headers present         |
| 6       | Oban background jobs        | High       | Async exports work      |
| 7       | Fly.io deployment           | High       | App deployed            |
| 8       | Database backup automation  | High       | Backups running         |
| 9       | LiveView streaming          | Medium     | Large lists perform     |
| 10      | Application caching         | Medium     | Faster repeated queries |
| 11      | Metrics dashboard           | Medium     | Metrics visible         |
| 12      | JS bundle optimization      | Medium     | Smaller bundles         |
| 13      | Audit logging               | Medium     | Actions tracked         |
| 14      | Loading states/skeletons    | Low        | Better UX               |
| 15      | Accessibility improvements  | Low        | WCAG compliance         |
| 16      | User documentation          | Low        | Docs available          |

---

## Success Criteria

- [ ] Application deployed and running on fly.io
- [ ] Error rate < 0.1% in production
- [ ] p95 response time < 500ms
- [ ] Zero critical security vulnerabilities (Sobelow clean)
- [ ] Automated database backups running
- [ ] Monitoring dashboards operational
- [ ] Health checks passing
- [ ] Runbooks documented and tested
- [ ] User documentation available

---

## Pre-Launch Checklist

- [ ] All environment variables configured
- [ ] Database migrations run successfully
- [ ] OAuth providers configured for production URLs
- [ ] Email sending verified (Resend)
- [ ] File storage verified (R2)
- [ ] SSL certificate active
- [ ] DNS configured
- [ ] Monitoring alerts set up
- [ ] Backup/restore tested
- [ ] Load testing completed
- [ ] Security audit passed

---

*This phase should be completed before any public launch or beta release.*
