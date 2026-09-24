# Exclude E2E and compiler validation tests by default
# Run E2E with: mix test --include e2e
# Run ysc validation with: mix test --only ysc_validation (requires ysc in PATH)
# Run ink validation with: mix test --only ink_validation (requires inklecate in PATH)
ExUnit.start(exclude: [:e2e, :ysc_validation, :ink_validation], assert_receive_timeout: 500)

# Clean up test uploads after the entire suite finishes
ExUnit.after_suite(fn _result ->
  upload_dir =
    Application.get_env(:storyarn, :storage, [])[:upload_dir] || "priv/static/uploads/test"

  File.rm_rf!(upload_dir)
end)

Ecto.Adapters.SQL.Sandbox.mode(Storyarn.Repo, :manual)

# A test that commits data with Sandbox.unboxed_run must also remove the Oban
# jobs that data enqueued: no foreign key does it, and a committed job outlives
# the run and breaks any test that inspects the queue. Only jobs inserted by
# this run count, so rows left by an earlier run do not fail this one.
require Ecto.Query

oban_job_baseline =
  Ecto.Adapters.SQL.Sandbox.unboxed_run(Storyarn.Repo, fn ->
    Storyarn.Repo.one(Ecto.Query.from(job in Oban.Job, select: max(job.id)))
  end) || 0

ExUnit.after_suite(fn _result ->
  leaked =
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Storyarn.Repo, fn ->
      Storyarn.Repo.all(
        Ecto.Query.from(job in Oban.Job,
          where: job.id > ^oban_job_baseline,
          order_by: job.id,
          select: %{id: job.id, worker: job.worker, args: job.args}
        )
      )
    end)

  if leaked != [] do
    raise """
    #{length(leaked)} Oban job(s) were committed outside the SQL sandbox and outlived the test run:

    #{Enum.map_join(leaked, "\n", &"  #{&1.id} #{&1.worker} #{inspect(&1.args)}")}

    The test that inserted them committed data with Sandbox.unboxed_run. Delete
    the jobs its data enqueued in that test's cleanup.
    """
  end
end)

# Import factory functions globally in tests
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Configure base URL for PhoenixTest Playwright (E2E tests)
test_port = System.get_env("MIX_TEST_PORT", "4002")
Application.put_env(:phoenix_test, :base_url, "http://127.0.0.1:#{test_port}")

# The Mix alias selects browser mode before runtime config loads. Location
# filters are only installed by Mix after this helper, so use the same decision.
if System.get_env("STORYARN_E2E_TESTS") == "true" do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end
