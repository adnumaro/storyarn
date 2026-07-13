# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ex_aws, :s3,
  scheme: "https://",
  region: "auto"

# ExAws configuration for Cloudflare R2 (S3-compatible)
# Credentials are configured in runtime.exs
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Req

# LiveVue configuration
config :live_vue,
  ssr: false,
  gettext_backend: Storyarn.Gettext

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id]

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

# Oban background job processing
config :storyarn, Oban,
  engine: Oban.Engines.Basic,
  repo: Storyarn.Repo,
  queues: [default: 10, snapshots: 2, templates: 1, template_installs: 2, localization: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Storyarn.Workers.DailySnapshotWorker},
       {"0 4 * * *", Storyarn.Workers.SnapshotRetentionWorker},
       {"0 * * * *", Storyarn.Workers.TrashRetentionWorker}
     ]}
  ]

# Configure Gettext locales
config :storyarn, Storyarn.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# Configures the mailer
# Development uses Mailpit (SMTP on localhost:1025, UI on localhost:8025)
# Production uses Resend API (configured in runtime.exs)
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local

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

config :storyarn, :admin_email, "adan@storyarn.com"

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
  version: "4.1.7",
  storyarn: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
