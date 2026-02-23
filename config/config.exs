# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

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

# Configures the mailer
# Development uses Mailpit (SMTP on localhost:1025, UI on localhost:8025)
# Production uses Resend API (configured in runtime.exs)
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local

# Email sender configuration (name and email address for outgoing emails)
config :storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"}

# Configure Swoosh API client (needed for Resend in production)
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  storyarn: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

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

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, ["password", "secret", "token", "api_key", "_csrf_token"]

# Configure Gettext locales
config :storyarn, StoryarnWeb.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# Disable Tesla deprecation warning (used by OAuth libraries)
config :tesla, disable_deprecated_builder_warning: true

# Configure Hammer rate limiting
# Using ETS backend for simplicity (suitable for single-node deployments)
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# ExAws configuration for Cloudflare R2 (S3-compatible)
# Credentials are configured in runtime.exs
config :ex_aws,
  json_codec: Jason

config :ex_aws, :s3,
  scheme: "https://",
  region: "auto"

# Ueberauth OAuth configuration
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]},
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email"]}
  ]

# OAuth provider credentials (configured in runtime.exs for production)
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")

# Cloak encryption configuration
# Development key - NEVER use in production!
# Generate production key with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
config :storyarn, Storyarn.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      # This is a development-only key, override in production via CLOAK_KEY env var
      tag: "AES.GCM.V1",
      key: Base.decode64!("dGhpc2lzYWRldmVsb3BtZW50a2V5b25seTMyYnl0ZXM="),
      iv_length: 12
    }
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
