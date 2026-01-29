ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Storyarn.Repo, :manual)

# Import factory functions globally in tests
{:ok, _} = Application.ensure_all_started(:ex_machina)
