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
  metadata: [:request_id]

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

# Sentry error tracking (DSN configured in runtime.exs for production)
config :sentry,
  client: Sentry.HackneyClient,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  environment_name: config_env(),
  filter: Sentry.DefaultEventFilter

# Oban background job processing
config :storyarn, Oban,
  engine: Oban.Engines.Basic,
  repo: Storyarn.Repo,
  queues: [default: 10, snapshots: 2],
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

config :ueberauth, StoryarnWeb.OAuth.DiscordOAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")

# Ueberauth OAuth configuration
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]},
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    discord: {StoryarnWeb.OAuth.DiscordStrategy, [default_scope: "identify email"]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# OAuth provider credentials (configured in runtime.exs for production)
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

import_config "#{config_env()}.exs"
