# Exclude E2E tests by default (run with: mix test --include e2e)
ExUnit.start(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Storyarn.Repo, :manual)

# Ensure Lucideicons module is loaded so icon atoms exist for binary_to_existing_atom
Code.ensure_loaded!(Lucideicons)

# Import factory functions globally in tests
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Configure base URL for PhoenixTest Playwright (E2E tests)
Application.put_env(:phoenix_test, :base_url, "http://127.0.0.1:4002")

# Start Playwright supervisor for E2E tests
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
