defmodule Storyarn.Architecture.IdeationInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/ideation"
  @session_roles ~w(adapters commands entities events execution queries)
  @roles ~w(adapters commands contracts entities events execution queries rules)
  @capabilities ~w(ideas recovery sessions)
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
      recover_session: 4,
      purge_replaced_session: 4,
      subscribe_sessions: 2,
      update_session: 5
    ]

    idea_operations = [
      create_canvas_idea: 4,
      derive_canvas_idea: 6,
      update_canvas_idea: 6,
      set_private_mode: 5,
      delete_idea: 5,
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
      unsubscribe_ideas: 3,
      connect_ideas: 6,
      update_idea_canvas: 6,
      update_idea: 6
    ]

    assert Storyarn.Ideation.__info__(:functions) ==
             Enum.sort(
               expected ++
                 idea_operations ++ [capture_recovery: 1, validate_recovery: 1, restore_recovery: 2, verify_recovery: 3]
             )

    assert Storyarn.Ideation.Ideas.__info__(:functions) == Enum.sort(idea_operations)

    assert Storyarn.Ideation.Sessions.__info__(:functions) ==
             Enum.sort(
               expected ++
                 [lock_for_contribution: 3, set_canvas_mode_locked: 3, notify_canvas_mode: 2, canvas_settings_query: 0]
             )
  end

  test "the recovery inventory cannot silently omit newly persisted fields" do
    schemas = %{
      "sessions" => Storyarn.Ideation.Sessions.Session,
      "session_revisions" => Storyarn.Ideation.Sessions.Revision,
      "ideas" => Storyarn.Ideation.Ideas.Idea,
      "revisions" => Storyarn.Ideation.Ideas.Revision,
      "edits" => Storyarn.Ideation.Ideas.Edit,
      "reveals" => Storyarn.Ideation.Ideas.Reveal,
      "publications" => Storyarn.Ideation.Ideas.Publication
    }

    for {collection, table, _, fields} <- Storyarn.Ideation.Recovery.Inventory.tables() do
      schema = Map.fetch!(schemas, collection)
      assert schema.__schema__(:source) == table
      assert Enum.sort(fields) == Enum.sort(schema.__schema__(:fields))
    end
  end

  test "Ideation cannot read account identities through raw tables or Account schemas" do
    violations =
      Enum.filter(Path.wildcard("#{@root}/**/*.ex"), fn path ->
        Regex.match?(~r/"users"|:users\b|\bStoryarn\.Accounts\.User\b/, File.read!(path))
      end)

    assert violations == [], "Recovery identities belong to Accounts: #{inspect(violations)}"
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
