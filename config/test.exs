import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Disable feature-flag cache and PubSub notifications in tests. Toggles are
# read straight from Postgres so setting a flag in a test is immediately
# visible without dealing with stale cache entries.
config :fun_with_flags, :cache, enabled: false
config :fun_with_flags, :cache_bust_notifications, enabled: false

# Disable LiveVue props diffing so tests always see full props
config :live_vue, enable_props_diff: false

# Print only warnings and errors during test
config :logger, level: :warning

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
    assets_dir: ".",
    browser: :chromium,
    headless: System.get_env("PLAYWRIGHT_HEADLESS", "true") in ~w(t true 1),
    ecto_sandbox_stop_owner_delay: 1000,
    timeout: to_timeout(second: 10)
  ]

config :posthog,
  enable: true,
  enable_error_tracking: false,
  api_host: "https://eu.i.posthog.com",
  in_app_otp_apps: [:storyarn],
  test_mode: true,
  api_key: "phc_test"

# Oban: inline mode for testing
config :storyarn, Oban, testing: :manual
config :storyarn, Storyarn.AI.CredentialResolver, StoryarnTest.AI.FakeCredentialResolver
config :storyarn, Storyarn.AI.InferenceProviders, providers: %{"fake" => Storyarn.AI.InferenceProviders.Fake}

config :storyarn, Storyarn.AI.InferenceProviders.Together,
  endpoint: "https://fake.test/v1/chat/completions",
  req_options: [plug: {Req.Test, StoryarnTest.AI.Together}]

# Route AI-provider validation calls through Req.Test stubs so no test opens
# an outbound socket. Each provider adapter has its own stub name so tests can
# scope expectations per provider.
config :storyarn, Storyarn.AI.Providers.Anthropic, req_options: [plug: {Req.Test, StoryarnTest.AI.Anthropic}]
config :storyarn, Storyarn.AI.Providers.DeepL, req_options: [plug: {Req.Test, StoryarnTest.AI.DeepL}]
config :storyarn, Storyarn.AI.Providers.DeepSeek, req_options: [plug: {Req.Test, StoryarnTest.AI.DeepSeek}]
config :storyarn, Storyarn.AI.Providers.Google, req_options: [plug: {Req.Test, StoryarnTest.AI.Google}]
config :storyarn, Storyarn.AI.Providers.Mistral, req_options: [plug: {Req.Test, StoryarnTest.AI.Mistral}]
config :storyarn, Storyarn.AI.Providers.Moonshot, req_options: [plug: {Req.Test, StoryarnTest.AI.Moonshot}]
config :storyarn, Storyarn.AI.Providers.OpenAI, req_options: [plug: {Req.Test, StoryarnTest.AI.OpenAI}]

config :storyarn, Storyarn.AI.RouteResolver,
  managed: [
    enabled: true,
    provider: "fake",
    model: "deterministic-v1",
    credential_ref: "test-managed",
    payer: "storyarn",
    assignment_source: "contract_test",
    consent_basis: "workspace_policy",
    verified_eu_region: true,
    verified_zdr: true,
    endpoint: "https://fake.test/v1/chat/completions",
    region: "eu-test",
    provider_price: [
      version: 1,
      currency: "USD",
      input_per_million: "0",
      output_per_million: "0",
      max_estimated_cost: "0"
    ],
    budget: [global_daily: "100", global_monthly: "1000", workspace_daily: "10"]
  ]

config :storyarn, Storyarn.AI.Settlement, StoryarnTest.AI.FakeSettlement

# Slice-2 contract tests use a deterministic provider and non-financial fake
# settlement. Production keeps every one of these boundaries unavailable.
config :storyarn, Storyarn.AI.TaskRegistry, tasks: [StoryarnTest.AI.ContractTask]

# In test we don't send emails
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Test

# Disable rate limiting in tests
config :storyarn, Storyarn.RateLimiter, enabled: false

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
  pool_size: System.schedulers_online() * 2,
  queue_target: 500,
  queue_interval: 1000

# Existing restore contract tests exercise the implementation with restores
# enabled. Containment tests override this configuration explicitly.
config :storyarn, Storyarn.Versioning.RestorePolicy,
  sheet_version_restore: true,
  flow_version_restore: true,
  scene_version_restore: true,
  project_snapshot_restore: true,
  deleted_project_recovery: true

# Server is enabled for E2E tests (Playwright requires a running server)
config :storyarn, StoryarnWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("MIX_TEST_PORT", "4002"))],
  secret_key_base: "FeJDhWpJbfABMyHLm9bPO4lWdhmwJVzNdRuhnukQFhXRYMedUbeO/fZg+/TfwqMK",
  server: true,
  check_origin: false

# Enable SQL sandbox for E2E tests with Playwright
config :storyarn, :sql_sandbox, true

# Isolate test file uploads from dev (prevents polluting priv/static/uploads/)
config :storyarn, :storage,
  adapter: :local,
  upload_dir: "priv/static/uploads/test",
  public_path: "/uploads/test"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
