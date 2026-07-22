# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Keep every object-storage socket phase bounded well below the import-plan
# reservation lease. The importer also wraps the whole PUT in a wall-clock
# deadline because a send timeout only limits individual blocked writes.
alias Storyarn.Workers.DailySnapshotWorker
alias Storyarn.Workers.ExpireAIResultsWorker
alias Storyarn.Workers.SnapshotRetentionWorker
alias Storyarn.Workers.TrashRetentionWorker

config :ex_aws, :req_opts,
  receive_timeout: 60_000,
  pool_timeout: 10_000,
  connect_options: [timeout: 30_000, transport_opts: [send_timeout: 60_000]]

config :ex_aws, :s3,
  scheme: "https://",
  region: "auto"

# ExAws configuration for Cloudflare R2 (S3-compatible)
# Credentials are configured in runtime.exs
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Req

# Feature flags — Postgres-backed with per-node cache invalidated via PubSub.
# Runtime toggling supports gradual rollout to individual users during beta.
config :fun_with_flags, :cache,
  enabled: true,
  ttl: 900

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Storyarn.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Storyarn.Repo,
  ecto_table_name: "fun_with_flags_toggles"

# LiveVue configuration
config :live_vue,
  ssr: false,
  gettext_backend: Storyarn.Gettext

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Yarn Spinner source files are plain text but have no IANA-registered media
# type. Register the extension so LiveView uploads can keep an explicit accept
# list; server-side format and archive validation remains authoritative.
config :mime, :types, %{"text/x-yarn-spinner" => ["yarn"]}

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, ["password", "secret", "token", "api_key", "_csrf_token"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix_vite, PhoenixVite.Npm,
  assets: [args: [], cd: Path.expand("..", __DIR__)],
  vite: [
    args: ~w(exec -- vite),
    cd: Path.expand("..", __DIR__),
    env: %{"MIX_BUILD_PATH" => Mix.Project.build_path()}
  ]

# PostHog product analytics and error tracking are enabled only from runtime
# config once a project API key is present.
config :posthog,
  enable: false,
  enable_error_tracking: false,
  in_app_otp_apps: [:storyarn]

# Daily backup creation remains active, but automatic deletion of older
# recovery points is frozen.
config :storyarn, DailySnapshotWorker, pruning_enabled: false

# Oban background job processing
config :storyarn, Oban,
  engine: Oban.Engines.Basic,
  repo: Storyarn.Repo,
  queues: [
    default: 10,
    snapshots: 2,
    project_restores: 1,
    templates: 1,
    template_installs: 2,
    localization: 2,
    imports: 2,
    ai: 2,
    storage_cleanup: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", DailySnapshotWorker},
       {"0 4 * * *", SnapshotRetentionWorker},
       {"0 * * * *", TrashRetentionWorker},
       {"*/15 * * * *", Storyarn.Workers.ExpireProjectImportsWorker},
       {"*/15 * * * *", ExpireAIResultsWorker},
       {"*/5 * * * *", Storyarn.Workers.ReconcileAIReservationsWorker},
       {"* * * * *", Storyarn.Workers.RetryStorageCleanupRequestsWorker}
     ]}
  ]

# Automatic retention for deleted-project snapshots is frozen during the
# recovery hardening phase. The worker also refuses to hard-delete projects.
config :storyarn, SnapshotRetentionWorker, enabled: false
config :storyarn, Storyarn.AI.CredentialResolver, Storyarn.AI.CredentialResolver.Unavailable
config :storyarn, Storyarn.AI.InferenceProviders, providers: %{}
config :storyarn, Storyarn.AI.RouteOptions, ttl_seconds: 300
config :storyarn, Storyarn.AI.RouteResolver, managed: nil
config :storyarn, Storyarn.AI.Settlement, Storyarn.AI.Settlement.Unavailable

# Slice 2 defines execution contracts but deliberately ships with no
# production task, route, credential resolver, or allowance implementation.
config :storyarn, Storyarn.AI.TaskRegistry, tasks: []

# Configure Gettext locales
config :storyarn, Storyarn.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# Configures the mailer
# Development uses Mailpit (SMTP on localhost:1025, UI on localhost:8025)
# Production uses Resend API (configured in runtime.exs)
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local

# Public, indexable locales are deliberately configured separately from
# Gettext. A locale can be available inside the authenticated application
# before its landing page, docs, legal copy, and editorial content are ready
# to be published under a canonical URL.
config :storyarn, Storyarn.Publication.Locales,
  default_locale: "en",
  locales: [
    %{gettext_locale: "en", language_tag: "en", path_segment: "en"},
    %{gettext_locale: "es", language_tag: "es", path_segment: "es"}
  ]

# Cloak encryption configuration
# Development key - NEVER use in production!
# Generate production key with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
config :storyarn, Storyarn.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      # This is a development-only key, override in production via CLOAK_KEY env var
      tag: "AES.GCM.V1", key: Base.decode64!("dGhpc2lzYWRldmVsb3BtZW50a2V5b25seTMyYnl0ZXM="), iv_length: 12
    }
  ]

# Restores remain disabled by default while their referential-integrity
# guarantees are being hardened. Runtime configuration can enable each surface
# independently after it passes audit.
config :storyarn, Storyarn.Versioning.RestorePolicy,
  sheet_version_restore: false,
  flow_version_restore: false,
  scene_version_restore: false,
  project_snapshot_restore: false,
  deleted_project_recovery: false

# Configures the endpoint
config :storyarn, StoryarnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StoryarnWeb.ErrorHTML, json: StoryarnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Storyarn.PubSub,
  live_view: [signing_salt: "ox8oI2KY"],
  # Session cookie salts - override in production via env vars
  session_signing_salt: "Fnke9Hmj",
  session_encryption_salt: "cV3kP8mQ"

# Automatic trash hard-deletion is frozen while restore and referential
# integrity are being hardened.
config :storyarn, TrashRetentionWorker, enabled: false
config :storyarn, :admin_email, "adan@storyarn.com"

config :storyarn,
       :import_idempotency_secret,
       :crypto.mac(
         :hmac,
         :sha256,
         Base.decode64!("dGhpc2lzYWRldmVsb3BtZW50a2V5b25seTMyYnl0ZXM="),
         "storyarn/import-idempotency/v1"
       )

# Email sender configuration (name and email address for outgoing emails)
config :storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"}

# Frontend PostHog boot is optional. The SDK config above remains the source for
# api_host/api_key; this only controls whether root metadata initializes the
# browser client.
config :storyarn, :posthog_frontend,
  frontend_enabled: false,
  error_tracking_enabled: false

config :storyarn, :scopes,
  user: [
    default: true,
    module: Storyarn.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Storyarn.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :storyarn,
  ecto_repos: [Storyarn.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Swoosh API client (needed for Resend in production)
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure tailwind (the version is required)
config :tailwind,
  # Import environment specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  version: "4.1.7",
  storyarn: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
