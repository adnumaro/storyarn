defmodule Storyarn.Architecture.IdeationInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/ideation"
  @roles ~w(adapters commands entities execution queries)
  @forbidden_role_edges [
    {"queries", "commands"},
    {"queries", "execution"},
    {"queries", "adapters"},
    {"entities", "commands"},
    {"entities", "queries"},
    {"entities", "execution"},
    {"entities", "adapters"},
    {"adapters", "commands"},
    {"adapters", "queries"},
    {"adapters", "execution"}
  ]

  test "Ideation declares its ownership and keeps only capability directories" do
    assert File.read!("#{@root}/README.md") =~ "## Write ownership and recovery"
    assert directories_in(@root) == ["sessions"]
    assert Path.wildcard("#{@root}/*.ex") == []
  end

  test "Sessions has one capability facade and places schemas under entities" do
    assert directories_in("#{@root}/sessions") == @roles
    assert Path.wildcard("#{@root}/sessions/*.ex") == ["#{@root}/sessions/sessions.ex"]

    assert Path.wildcard("#{@root}/sessions/entities/*.ex") == [
             "#{@root}/sessions/entities/configuration.ex",
             "#{@root}/sessions/entities/revision.ex",
             "#{@root}/sessions/entities/session.ex"
           ]
  end

  test "queries stay read-only and do not acquire locks or own transactions" do
    violations =
      Enum.filter(Path.wildcard("#{@root}/sessions/queries/**/*.ex"), fn path ->
        Regex.match?(
          ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback)\b|\bEcto\.Multi\b|lock:\s*"FOR /,
          File.read!(path)
        )
      end)

    assert violations == [], "Ideation queries must stay read-only: #{inspect(violations)}"
  end

  test "entities have no persistence I/O or query orchestration" do
    violations =
      Enum.filter(Path.wildcard("#{@root}/sessions/entities/**/*.ex"), fn path ->
        source = File.read!(path)
        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [], "Ideation entities must stay passive: #{inspect(violations)}"
  end

  test "root facade cannot bypass the capability facade" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(@roles, fn role ->
      assert denial?(policy, "lib/storyarn/ideation.ex", "#{@root}/sessions/#{role}/")
    end)
  end

  test "the ratchet enforces role direction" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(@forbidden_role_edges, fn {source, target} ->
      assert denial?(policy, "#{@root}/sessions/#{source}/", "#{@root}/sessions/#{target}/")
    end)
  end

  test "only the agreed transport-neutral operations are exposed" do
    expected = [
      archive_session: 4,
      assign_session_responsibilities: 5,
      create_session: 3,
      get_session: 3,
      list_session_revisions: 3,
      list_session_revisions: 4,
      list_sessions: 2,
      list_sessions: 3,
      reopen_session: 4,
      update_session: 5
    ]

    assert Storyarn.Ideation.__info__(:functions) == expected
    assert Storyarn.Ideation.Sessions.__info__(:functions) == expected
  end

  defp directories_in(path) do
    path |> File.ls!() |> Enum.filter(&File.dir?(Path.join(path, &1))) |> Enum.sort()
  end

  defp denial?(policy, source, target) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source and denial.target_root == target and
        denial.kinds == ["runtime", "export", "compile"]
    end)
  end
end
