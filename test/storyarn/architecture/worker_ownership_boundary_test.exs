defmodule Storyarn.Architecture.WorkerOwnershipBoundaryTest do
  use ExUnit.Case, async: true

  @sealed_worker_owners ~w(accounts localization platform projects workspaces)
  @recognized_worker_owners ~w(accounts ai flows localization platform projects scenes sheets workspaces)

  test "workers are grouped by owner while retaining the stable flat Oban identity" do
    worker_files = Path.wildcard("lib/storyarn/workers/**/*.ex")

    assert worker_files != []
    assert Path.wildcard("lib/storyarn/workers/*.ex") == []

    for path <- worker_files do
      relative_path = Path.relative_to(path, "lib/storyarn/workers")
      [owner, _file] = Path.split(relative_path)
      source = File.read!(path)

      assert owner in @recognized_worker_owners,
             "#{path} must live in a recognized bounded-context owner slice"

      assert source =~ ~r/^defmodule Storyarn\.Workers\.[A-Z][A-Za-z0-9]*Worker do/m,
             "#{path} must preserve the flat Storyarn.Workers.* Oban identity"

      refute source =~ "RollingRename"
    end
  end

  test "the architecture ratchet assigns every sealed worker slice to its owner" do
    {policy, _binding} = Code.eval_file("config/architecture_boundaries.exs")

    for owner <- @sealed_worker_owners do
      boundary = String.to_existing_atom(owner)

      assert "lib/storyarn/workers/#{owner}/" in Map.fetch!(policy.boundaries, boundary)
    end

    assert "lib/storyarn/workers/" in policy.boundaries.infrastructure
  end

  test "the abandoned worker rename compatibility does not return" do
    refute File.exists?("lib/storyarn/workers/rolling_rename.ex")
    refute File.exists?("priv/repo/migrations/20260824210000_rename_oban_worker_modules.exs")
    refute File.exists?("priv/repo/migrations/20260825120000_restore_legacy_oban_worker_names.exs")
    assert Path.wildcard("lib/storyarn/**/workers/legacy/*.ex") == []
  end
end
