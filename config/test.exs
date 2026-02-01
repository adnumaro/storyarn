import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Enable SQL sandbox for E2E tests with Playwright
config :storyarn, :sql_sandbox, true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :storyarn, Storyarn.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "storyarn_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Server is enabled for E2E tests (Playwright requires a running server)
config :storyarn, StoryarnWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FeJDhWpJbfABMyHLm9bPO4lWdhmwJVzNdRuhnukQFhXRYMedUbeO/fZg+/TfwqMK",
  server: true,
  check_origin: false

# In test we don't send emails
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable rate limiting in tests
config :storyarn, Storyarn.RateLimiter, enabled: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# PhoenixTest configuration for E2E tests
config :phoenix_test,
  otp_app: :storyarn,
  endpoint: StoryarnWeb.Endpoint,
  playwright: [
    assets_dir: "assets",
    browser: :chromium,
    headless: System.get_env("PLAYWRIGHT_HEADLESS", "true") in ~w(t true 1)
  ]
