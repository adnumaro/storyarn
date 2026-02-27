# Exclude E2E and ysc validation tests by default
# Run E2E with: mix test --include e2e
# Run ysc validation with: mix test --only ysc_validation (requires ysc in PATH)
ExUnit.start(exclude: [:e2e, :ysc_validation])
Ecto.Adapters.SQL.Sandbox.mode(Storyarn.Repo, :manual)

# Ensure Lucideicons module is loaded so icon atoms exist for binary_to_existing_atom
Code.ensure_loaded!(Lucideicons)

# Import factory functions globally in tests
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Configure base URL for PhoenixTest Playwright (E2E tests)
Application.put_env(:phoenix_test, :base_url, "http://127.0.0.1:4002")

# Start Playwright supervisor only when Playwright is installed (not in CI unit test job)
if File.dir?(Path.join(["assets", "node_modules", "playwright"])) do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end
