defmodule Storyarn.Architecture.IdeationInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/ideation"
  @session_roles ~w(adapters commands entities execution queries)
  @roles ~w(adapters commands contracts entities events execution queries rules)
  @capabilities ~w(ideas sessions)
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
    assert directories_in(@root) == @capabilities
    assert Path.wildcard("#{@root}/*.ex") == []
  end

  test "Sessions has one capability facade and places schemas under entities" do
    assert directories_in("#{@root}/sessions") == @session_roles
    assert Path.wildcard("#{@root}/sessions/*.ex") == ["#{@root}/sessions/sessions.ex"]

    assert Path.wildcard("#{@root}/sessions/entities/*.ex") == [
             "#{@root}/sessions/entities/configuration.ex",
             "#{@root}/sessions/entities/revision.ex",
             "#{@root}/sessions/entities/session.ex"
           ]
  end

  test "Ideas has a single capability facade with role-specific implementation" do
    assert directories_in("#{@root}/ideas") == ~w(commands contracts entities events execution queries rules)
    assert Path.wildcard("#{@root}/ideas/*.ex") == ["#{@root}/ideas/ideas.ex"]

    assert "#{@root}/ideas/entities/*.ex" |> Path.wildcard() |> Enum.map(&Path.basename/1) ==
             ~w(edit.ex idea.ex publication.ex reveal.ex revision.ex)
  end

  test "queries stay read-only and do not acquire locks or own transactions" do
    violations =
      Enum.filter(Path.wildcard("#{@root}/*/queries/**/*.ex"), fn path ->
        Regex.match?(
          ~r/\bRepo\.(?:insert|insert!|insert_all|update|update!|update_all|delete|delete!|delete_all|transact|transaction|rollback)\b|\bEcto\.Multi\b|lock:\s*"FOR /,
          File.read!(path)
        )
      end)

    assert violations == [], "Ideation queries must stay read-only: #{inspect(violations)}"
  end

  test "entities have no persistence I/O or query orchestration" do
    violations =
      Enum.filter(Path.wildcard("#{@root}/*/{entities,rules,contracts}/**/*.ex"), fn path ->
        source = File.read!(path)
        source =~ "Storyarn.Repo" or source =~ "Ecto.Query" or Regex.match?(~r/\bRepo\./, source)
      end)

    assert violations == [], "Ideation entities must stay passive: #{inspect(violations)}"
  end

  test "root facade cannot bypass the capability facade" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for capability <- @capabilities, role <- @roles do
      assert denial?(policy, "lib/storyarn/ideation.ex", "#{@root}/#{capability}/#{role}/")
    end
  end

  test "the ratchet enforces role direction" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for capability <- @capabilities, {source, target} <- @forbidden_role_edges do
      assert denial?(policy, "#{@root}/#{capability}/#{source}/", "#{@root}/#{capability}/#{target}/")
    end
  end

  test "capabilities cannot consume private modules from each other" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for source <- @capabilities, target <- @capabilities -- [source], role <- @roles do
      assert denial?(policy, "#{@root}/#{source}/", "#{@root}/#{target}/#{role}/")
    end
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

    idea_operations = [
      count_ideas: 3,
      create_idea: 4,
      derive_idea: 6,
      get_idea: 4,
      get_idea_edit: 5,
      get_idea_reveal: 4,
      list_idea_conflicts: 4,
      list_idea_conflicts: 5,
      list_idea_revisions: 4,
      list_idea_revisions: 5,
      list_ideas: 3,
      list_ideas: 4,
      prepare_idea_reveal: 4,
      prepare_idea_reveal: 5,
      reveal_ideas: 4,
      subscribe_ideas: 3,
      update_idea: 6
    ]

    assert Storyarn.Ideation.__info__(:functions) == Enum.sort(expected ++ idea_operations)
    assert Storyarn.Ideation.Ideas.__info__(:functions) == idea_operations
    assert Storyarn.Ideation.Sessions.__info__(:functions) == Enum.sort(expected ++ [lock_for_contribution: 3])
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
