defmodule Storyarn.Architecture.LocalizationWriteOwnershipTest do
  use ExUnit.Case, async: false

  alias Storyarn.Architecture.DependencyPolicy

  @moduletag timeout: 120_000

  @policy_path "config/architecture_boundaries.exs"
  @storyarn_root "lib/storyarn"
  @project_settings "lib/storyarn_web/live/project_settings_live/general.ex"
  @repo_write_functions ~w(
    delete delete! delete_all insert insert! insert_all insert_or_update insert_or_update!
    update update! update_all
  )a
  @repo_raw_sql_functions ~w(query query!)a
  @multi_write_functions ~w(delete delete_all insert insert_all insert_or_update merge run update update_all)a
  @sql_comment ~S"(?:/\*[\s\S]*?\*/|--[^\r\n]*(?:\r?\n|$))"
  @sql_gap "(?:\\s|#{@sql_comment})+"
  @sql_optional_gap "(?:\\s|#{@sql_comment})*"
  @sql_identifier ~S/(?:(?:"(?:[^"]|"")*")|(?:[a-z_][a-z0-9_$]*))/
  @qualified_sql_identifier "(?:(?:#{@sql_identifier})#{@sql_optional_gap}" <>
                              "\\.#{@sql_optional_gap})?#{@sql_identifier}"
  @qualified_project_languages "(?:(?:#{@sql_identifier})#{@sql_optional_gap}" <>
                                 "\\.#{@sql_optional_gap})?" <>
                                 "(?:\"project_languages\"|project_languages)(?![a-z0-9_$])"
  @sql_mutation_pattern Regex.compile!(
                          "\\b(?:INSERT#{@sql_gap}INTO|UPDATE(?:#{@sql_gap}ONLY)?|" <>
                            "DELETE#{@sql_gap}FROM|MERGE#{@sql_gap}INTO|" <>
                            "TRUNCATE(?:#{@sql_gap}TABLE)?)\\b",
                          "i"
                        )
  @copy_from_pattern Regex.compile!(
                       "\\bCOPY#{@sql_gap}#{@qualified_sql_identifier}" <>
                         "(?:#{@sql_optional_gap}\\([^)]*\\))?#{@sql_gap}FROM\\b",
                       "i"
                     )
  @table_sql_mutation_pattern Regex.compile!(
                                "\\b(?:INSERT#{@sql_gap}INTO(?:#{@sql_gap}ONLY)?|" <>
                                  "UPDATE(?:#{@sql_gap}ONLY)?|" <>
                                  "DELETE#{@sql_gap}FROM(?:#{@sql_gap}ONLY)?|" <>
                                  "MERGE#{@sql_gap}INTO(?:#{@sql_gap}ONLY)?)" <>
                                  "#{@sql_gap}#{@qualified_project_languages}",
                                "i"
                              )
  @truncate_table_reference "(?:ONLY#{@sql_gap})?#{@qualified_sql_identifier}" <>
                              "(?:#{@sql_optional_gap}\\*)?"
  @truncate_project_languages_reference "(?:ONLY#{@sql_gap})?#{@qualified_project_languages}" <>
                                          "(?:#{@sql_optional_gap}\\*)?"
  @truncate_table_sql_mutation_pattern Regex.compile!(
                                         "\\bTRUNCATE(?:#{@sql_gap}TABLE)?#{@sql_gap}" <>
                                           "(?:#{@truncate_table_reference}" <>
                                           "#{@sql_optional_gap},#{@sql_optional_gap})*" <>
                                           @truncate_project_languages_reference,
                                         "i"
                                       )
  @copy_from_table_pattern Regex.compile!(
                             "\\bCOPY#{@sql_gap}#{@qualified_project_languages}" <>
                               "(?:#{@sql_optional_gap}\\([^)]*\\))?#{@sql_gap}FROM\\b",
                             "i"
                           )

  test "Localization ordinary writers and privileged Project exceptions are exact contracts" do
    ownership = ownership_policy()

    assert ownership.table == "project_languages"
    assert ownership.ordinary_owner == :localization
    assert ownership.owner_paths == ["lib/storyarn/localization.ex", "lib/storyarn/localization/"]

    assert Enum.map(ownership.ordinary_writers, & &1.path) == [
             "lib/storyarn/localization/languages/commands/add.ex",
             "lib/storyarn/localization/languages/commands/change_source.ex",
             "lib/storyarn/localization/languages/commands/remove.ex",
             "lib/storyarn/localization/languages/commands/reorder.ex",
             "lib/storyarn/localization/languages/commands/update.ex",
             "lib/storyarn/localization/languages/adapters/positions/postgres.ex"
           ]

    schema_modules = table_schema_modules()

    for writer <- ownership.ordinary_writers do
      assert File.regular?(writer.path), "ordinary writer path is missing: #{writer.path}"
      assert_metadata!(writer, [:role, :reason, :transaction, :locks_or_preconditions])

      assert declared_writer_effect?(writer, schema_modules),
             "declared writer has no reviewed table effect: #{writer.path}"
    end

    assert ownership.privileged_project_writers |> Map.keys() |> Enum.sort() ==
             [:import_reconstitution, :project_materialization_and_recovery, :repair]

    for {_name, contract} <- ownership.privileged_project_writers do
      assert_metadata!(contract, [:operation, :reason, :transaction, :locks_or_preconditions])

      for writer <- contract.writers do
        assert File.regular?(writer.path), "privileged writer path is missing: #{writer.path}"

        actual =
          writer.path
          |> File.read!()
          |> project_languages_mutating_functions(schema_modules)

        assert actual == MapSet.new(writer.functions), """
        #{writer.path} may mutate project_languages only inside the exact
        reviewed functions.

        Actual: #{actual |> MapSet.to_list() |> Enum.sort() |> inspect()}
        Expected: #{inspect(Enum.sort(writer.functions))}
        """
      end
    end

    assert ownership.privileged_project_writers.repair.writers == []
  end

  test "every owner table mutation stays in the exact ordinary-writer allowlist" do
    ownership = ownership_policy()
    schema_modules = table_schema_modules()

    actual =
      source_paths()
      |> Enum.filter(fn path ->
        owner_path?(path, ownership) and
          project_languages_mutation?(File.read!(path), schema_modules)
      end)
      |> Enum.sort()

    expected =
      ownership.ordinary_writers
      |> Enum.reject(&(&1.role == :command_orchestrator))
      |> Enum.map(& &1.path)
      |> Enum.sort()

    assert actual == expected, """
    Every Localization source that directly mutates project_languages must be
    named exactly. A new command or adapter is not authorized by its folder.

    Actual: #{inspect(actual, pretty: true)}
    Expected: #{inspect(expected, pretty: true)}
    """
  end

  test "every foreign schema and consumer of project_languages stays classified globally" do
    ownership = ownership_policy()

    assert foreign_table_consumers(ownership) == declared_foreign_consumers(ownership), """
    Every foreign schema mapping, grouped/prefixed alias consumer and direct SQL
    reference to project_languages must be classified explicitly.

    Actual: #{inspect(foreign_table_consumers(ownership), pretty: true)}
    Declared: #{inspect(declared_foreign_consumers(ownership), pretty: true)}
    """
  end

  test "foreign read-only consumers contain no Repo, raw SQL or Ecto.Multi mutation" do
    for path <- strict_foreign_readers(ownership_policy()) do
      refute persistence_mutation?(File.read!(path)),
             "#{path} is declared read-only but contains a persistence mutation"
    end
  end

  test "mixed foreign consumers stay content-pinned until their other writes are separated" do
    for consumer <- ownership_policy().reviewed_mixed_foreign_consumers do
      assert File.regular?(consumer.path)
      assert byte_size(consumer.reason) > 0

      assert sha256(consumer.path) == consumer.reviewed_sha256, """
      #{consumer.path} both reads project_languages and writes another table.
      Review any change and refresh its fingerprint only after confirming that
      it still cannot write project_languages.
      """

      refute table_sql_mutation?(File.read!(consumer.path))
    end
  end

  test "restricted raw writer entrypoints keep only their named callers" do
    for entrypoint <- ownership_policy().restricted_entrypoints do
      assert File.regular?(entrypoint.path)
      assert byte_size(entrypoint.reason) > 0

      assert module_consumers(entrypoint.module, entrypoint.path) == Enum.sort(entrypoint.allowed_callers), """
      #{entrypoint.module} may only be called by its explicitly reviewed coordinators.
      """
    end
  end

  test "AST analysis rejects every previously identified alias and mutation bypass" do
    schema = "Storyarn.Projects.Persistence.ProjectLanguageRecord"
    schemas = [schema]

    assert persistence_mutation?("alias Ecto.Multi\nMulti.update(multi, :language, changeset)")
    assert persistence_mutation?("alias Storyarn.{Repo}\nRepo.delete(changeset)")
    assert persistence_mutation?("alias Storyarn.Repo, as: Persistence\nPersistence.update(changeset)")
    assert persistence_mutation?("sql = build_sql()\nRepo.query!(sql)")
    assert persistence_mutation?("import Storyarn.Repo\ninsert_or_update(changeset)")
    assert persistence_mutation?("repo.update(changeset)")
    assert persistence_mutation?("repo.query(dynamic_sql)")
    assert persistence_mutation?("repo.query!(dynamic_sql)")
    assert persistence_mutation?("alias Ecto.Multi\nMulti.insert_or_update(multi, :language, changeset)")
    assert persistence_mutation?("apply(Storyarn.Repo, :update, [changeset])")

    assert references_schema_module?("alias Storyarn.Projects.Persistence.{ProjectLanguageRecord}", schemas)

    assert references_schema_module?(
             "alias Storyarn.Projects.Persistence\nPersistence.ProjectLanguageRecord",
             schemas
           )

    assert references_schema_module?(
             "alias Storyarn.Projects.Persistence\n" <>
               "alias Persistence.{ProjectLanguageRecord}\nProjectLanguageRecord",
             schemas
           )

    assert references_schema_module?(
             "alias Storyarn.Projects\nProjects.LocalizationReconstitution.import_language(1, %{})",
             ["Storyarn.Projects.LocalizationReconstitution"]
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "query = from(row in ProjectLanguageRecord)\nRepo.update_all(query, set: [is_source: true])",
             schemas
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "changeset = ProjectLanguageRecord.create_changeset(record, attrs)\nRepo.update(changeset)",
             schemas
           )

    assert project_languages_mutation?(
             "import Storyarn.Repo\n" <>
               "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "changeset = ProjectLanguageRecord.create_changeset(record, attrs)\n" <>
               "insert_or_update(changeset)",
             schemas
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "def remove(%ProjectLanguageRecord{} = language), do: Repo.delete(language)",
             schemas
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "def update(%ProjectLanguageRecord{} = language, repo), do: repo.update(language)",
             schemas
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "def update(%ProjectLanguageRecord{} = language), " <>
               "do: apply(Storyarn.Repo, :update, [language])",
             schemas
           )

    assert project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "sql = build_sql()\nRepo.query!(sql)",
             schemas
           )

    refute project_languages_mutation?(
             "@sql \"UPDATE localized_texts SET status = 'pending'\"\nRepo.query!(@sql)",
             schemas
           )

    refute project_languages_mutation?(
             "alias Storyarn.Projects.Persistence.ProjectLanguageRecord\n" <>
               "alias Storyarn.Localization.LocalizedText\n" <>
               "languages = from(language in ProjectLanguageRecord, select: language.locale_code)\n" <>
               "Repo.update_all(from(text in LocalizedText, where: text.locale_code in subquery(languages)), set: [value: nil])",
             schemas
           )

    assert table_sql_mutation?(~s|Repo.query!("UPDATE ONLY project_languages SET position = 0")|)
    assert table_sql_mutation?(~s|Repo.query!("DELETE FROM ONLY project_languages WHERE id = 1")|)
    assert table_sql_mutation?(~s|Repo.query!("INSERT INTO ONLY project_languages (id) VALUES (1)")|)
    assert table_sql_mutation?(~s|Repo.query!("MERGE INTO public.project_languages USING incoming ON true")|)
    assert table_sql_mutation?(~s|Repo.query!("UPDATE ONLY \"public\" . \"project_languages\" SET position = 0")|)
    assert table_sql_mutation?(~s|Repo.query!("DELETE /* owner */ FROM /* target */ project_languages")|)
    assert table_sql_mutation?(~s|Repo.query!("INSERT -- owner\nINTO project_languages (id) VALUES (1)")|)
    assert table_sql_mutation?(~s|Repo.query!("INSERT INTO project_languages (id) VALUES (1)")|)
    assert table_sql_mutation?(~s|Repo.query!("DELETE FROM project_languages WHERE id = 1")|)
    assert table_sql_mutation?(~s|Repo.query!("TRUNCATE TABLE project_languages")|)
    assert table_sql_mutation?(~s|Repo.query!("TRUNCATE TABLE other_table, project_languages")|)
    assert table_sql_mutation?(~s|Repo.query!("TRUNCATE other_table, ONLY public . project_languages")|)
    assert table_sql_mutation?(~s|Repo.query!("COPY project_languages FROM STDIN")|)
    assert persistence_mutation?(~s|Repo.query!("COPY project_languages FROM STDIN")|)
    refute table_sql_mutation?(~s|Repo.query!("COPY project_languages TO STDOUT")|)
    refute persistence_mutation?(~s|Repo.query!("COPY project_languages TO STDOUT")|)
    refute persistence_mutation?("Repo.all(query)")
    refute table_sql_mutation?(~s|Repo.query!("SELECT * FROM project_languages")|)
  end

  test "Project lifecycle cannot regain the local language record" do
    policy = DependencyPolicy.load!(@policy_path)
    [project_record] = ownership_policy().privileged_project_schema_mappings

    assert Enum.any?(policy.path_denials, fn denial ->
             denial.source_root == "lib/storyarn/projects/lifecycle/" and
               denial.target_root == project_record and
               Enum.sort(denial.kinds) == ~w(compile export runtime)
           end)

    for path <- ["lib/storyarn/projects.ex", "lib/storyarn/projects/lifecycle/lifecycle.ex"] do
      source = File.read!(path)
      refute source =~ "ensure_source_language"
      refute source =~ "change_source_language"
      refute source =~ "source_language_option"
    end
  end

  test "Project settings enters source-language behavior through the public Localization facade" do
    policy = DependencyPolicy.load!(@policy_path)
    source = File.read!(@project_settings)

    assert source =~ "alias Storyarn.Localization"
    assert source =~ "Localization.ensure_source_language(project)"
    assert source =~ "Localization.change_source_language("
    assert source =~ "Localization.get_source_language(project.id)"

    refute source =~ "Projects.ensure_source_language"
    refute source =~ "Projects.change_source_language"
    refute source =~ "Projects.get_source_language"

    assert Enum.any?(policy.durable_contracts, fn contract ->
             contract.source == @project_settings and
               contract.target == "lib/storyarn/localization.ex" and
               contract.kinds == ["runtime"]
           end)
  end

  defp ownership_policy do
    @policy_path
    |> DependencyPolicy.load!()
    |> get_in([:persistence_ownership, :project_languages])
  end

  defp source_paths do
    @storyarn_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp table_schema_modules do
    source_paths()
    |> Enum.flat_map(fn path -> path |> File.read!() |> quoted!() |> schema_modules() end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp schema_modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, segments}, [do: body]]} = node, modules ->
          module = module_name(segments)
          if table_schema?(body), do: {node, [module | modules]}, else: {node, modules}

        node, modules ->
          {node, modules}
      end)

    modules
  end

  defp table_schema?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:schema, _meta, ["project_languages" | _rest]} = node, _found? -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp foreign_table_consumers(ownership) do
    schema_modules = table_schema_modules()

    source_paths()
    |> Enum.reject(&owner_path?(&1, ownership))
    |> Enum.filter(fn path ->
      source = File.read!(path)
      source =~ ~r/\bproject_languages\b/ or references_schema_module?(source, schema_modules)
    end)
    |> Enum.sort()
  end

  defp declared_foreign_consumers(ownership) do
    (Map.values(ownership.foreign_schema_mappings) ++
       [ownership.privileged_project_schema_mappings] ++
       Map.values(ownership.foreign_readers) ++
       [Enum.map(ownership.reviewed_mixed_foreign_consumers, & &1.path)] ++
       [privileged_project_writers(ownership)])
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp strict_foreign_readers(ownership) do
    (Map.values(ownership.foreign_schema_mappings) ++ Map.values(ownership.foreign_readers))
    |> List.flatten()
    |> Enum.sort()
  end

  defp privileged_project_writers(ownership) do
    ownership.privileged_project_writers
    |> Map.values()
    |> Enum.flat_map(& &1.writers)
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp owner_path?(path, ownership), do: Enum.any?(ownership.owner_paths, &String.starts_with?(path, &1))

  defp declared_writer_effect?(%{role: :command_orchestrator, path: path}, _schema_modules) do
    source = File.read!(path)

    references_schema_module?(
      source,
      ["Storyarn.Localization.Languages.Adapters.Positions.Postgres"]
    ) and source =~ "Postgres.set_positions("
  end

  defp declared_writer_effect?(writer, schema_modules) do
    writer.path |> File.read!() |> project_languages_mutation?(schema_modules)
  end

  defp module_consumers(module_name, defining_path) do
    source_paths()
    |> Enum.reject(&(&1 == defining_path))
    |> Enum.filter(&(&1 |> File.read!() |> references_schema_module?([module_name])))
    |> Enum.sort()
  end

  defp references_schema_module?(source, schema_modules) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)
    Enum.any?(schema_modules, &ast_references_module?(ast, &1, aliases))
  end

  defp persistence_mutation?(source) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)

    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        {node, found? or persistence_mutation_node?(node, aliases, imports)}
      end)

    found?
  end

  defp persistence_mutation_node?({{:., _, [{:__aliases__, _, segments}, function]}, _, arguments}, aliases, _imports) do
    modules = expanded_modules(segments, aliases)

    cond do
      repo_module?(modules) and function in @repo_write_functions -> true
      repo_module?(modules) and function in @repo_raw_sql_functions -> raw_sql_mutation?(arguments)
      multi_module?(modules) and function in @multi_write_functions -> true
      true -> false
    end
  end

  defp persistence_mutation_node?({{:., _, [_dynamic_receiver, function]}, _, arguments}, _aliases, _imports) do
    function in @repo_write_functions or
      (function in @repo_raw_sql_functions and raw_sql_mutation?(arguments)) or
      function in @multi_write_functions
  end

  defp persistence_mutation_node?({:apply, _, [module_ast, function, arguments]}, aliases, _imports)
       when is_atom(function) and is_list(arguments) do
    modules = module_ast_modules(module_ast, aliases)

    cond do
      repo_module?(modules) and function in @repo_write_functions -> true
      repo_module?(modules) and function in @repo_raw_sql_functions -> raw_sql_mutation?(arguments)
      multi_module?(modules) and function in @multi_write_functions -> true
      true -> false
    end
  end

  defp persistence_mutation_node?({function, _, arguments}, _aliases, imports)
       when is_atom(function) and is_list(arguments) do
    ("Storyarn.Repo" in imports and function in @repo_write_functions) or
      ("Storyarn.Repo" in imports and function in @repo_raw_sql_functions and raw_sql_mutation?(arguments)) or
      ("Ecto.Multi" in imports and function in @multi_write_functions)
  end

  defp persistence_mutation_node?(_node, _aliases, _imports), do: false

  defp project_languages_mutation?(source, schema_modules) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    sql_literals = sql_literals(ast)
    tainted = tainted_variables(ast, schema_modules, aliases)

    project_languages_mutation_ast?(
      ast,
      schema_modules,
      aliases,
      imports,
      sql_literals,
      tainted
    )
  end

  defp project_languages_mutating_functions(source, schema_modules) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)
    imports = imported_modules(ast, aliases)
    sql_literals = sql_literals(ast)
    tainted = tainted_variables(ast, schema_modules, aliases)

    {_ast, functions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {visibility, _meta, [head, body]} = node, functions
        when visibility in [:def, :defp] and is_list(body) ->
          identity = function_identity(visibility, head)

          functions =
            if identity &&
                 project_languages_mutation_ast?(
                   Keyword.fetch!(body, :do),
                   schema_modules,
                   aliases,
                   imports,
                   sql_literals,
                   tainted
                 ) do
              MapSet.put(functions, identity)
            else
              functions
            end

          {node, functions}

        node, functions ->
          {node, functions}
      end)

    functions
  end

  defp project_languages_mutation_ast?(ast, schema_modules, aliases, imports, sql_literals, tainted) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        {node,
         found? or
           table_mutation_node?(
             node,
             schema_modules,
             aliases,
             imports,
             sql_literals,
             tainted
           )}
      end)

    found?
  end

  defp function_identity(visibility, {:when, _, [head | _guards]}), do: function_identity(visibility, head)

  defp function_identity(visibility, {name, _, arguments}) when is_atom(name) and is_list(arguments),
    do: {visibility, name, length(arguments)}

  defp function_identity(_visibility, _head), do: nil

  defp table_mutation_node?({:|>, _, [left, right]}, schemas, aliases, imports, sql_literals, tainted) do
    case persistence_write_call(right, aliases, imports) do
      {kind, function, arguments} ->
        write_targets_schema?(
          kind,
          function,
          [left | arguments],
          schemas,
          aliases,
          sql_literals,
          tainted
        )

      nil ->
        false
    end
  end

  defp table_mutation_node?(node, schemas, aliases, imports, sql_literals, tainted) do
    case persistence_write_call(node, aliases, imports) do
      {kind, function, arguments} ->
        write_targets_schema?(
          kind,
          function,
          arguments,
          schemas,
          aliases,
          sql_literals,
          tainted
        )

      nil ->
        false
    end
  end

  defp persistence_write_call({{:., _, [{:__aliases__, _, segments}, function]}, _, arguments}, aliases, _imports) do
    modules = expanded_modules(segments, aliases)

    cond do
      repo_module?(modules) and function in @repo_write_functions -> {:repo, function, arguments}
      repo_module?(modules) and function in @repo_raw_sql_functions -> {:raw_repo, function, arguments}
      multi_module?(modules) and function in @multi_write_functions -> {:multi, function, arguments}
      true -> nil
    end
  end

  defp persistence_write_call({{:., _, [_dynamic_receiver, function]}, _, arguments}, _aliases, _imports)
       when function in @repo_write_functions do
    {:repo, function, arguments}
  end

  defp persistence_write_call({{:., _, [_dynamic_receiver, function]}, _, arguments}, _aliases, _imports)
       when function in @repo_raw_sql_functions do
    {:raw_repo, function, arguments}
  end

  defp persistence_write_call({:apply, _, [module_ast, function, arguments]}, aliases, _imports)
       when is_atom(function) and is_list(arguments) do
    modules = module_ast_modules(module_ast, aliases)

    cond do
      repo_module?(modules) and function in @repo_write_functions -> {:repo, function, arguments}
      repo_module?(modules) and function in @repo_raw_sql_functions -> {:raw_repo, function, arguments}
      multi_module?(modules) and function in @multi_write_functions -> {:multi, function, arguments}
      true -> nil
    end
  end

  defp persistence_write_call({function, _, arguments}, _aliases, imports)
       when is_atom(function) and is_list(arguments) do
    cond do
      "Storyarn.Repo" in imports and function in @repo_write_functions ->
        {:repo, function, arguments}

      "Storyarn.Repo" in imports and function in @repo_raw_sql_functions ->
        {:raw_repo, function, arguments}

      "Ecto.Multi" in imports and function in @multi_write_functions ->
        {:multi, function, arguments}

      true ->
        nil
    end
  end

  defp persistence_write_call(_node, _aliases, _imports), do: nil

  defp write_targets_schema?(:raw_repo, _function, arguments, _schemas, _aliases, sql_literals, _tainted) do
    raw_table_sql_mutation?(arguments, sql_literals)
  end

  defp write_targets_schema?(kind, function, arguments, schemas, aliases, _sql_literals, tainted) do
    target = persistence_target_argument(kind, arguments)

    if function in [:delete_all, :update_all] do
      query_targets_schema?(target, schemas, aliases, tainted)
    else
      expression_targets_schema?(target, schemas, aliases, tainted)
    end
  end

  defp persistence_target_argument(:repo, arguments), do: Enum.at(arguments, 0)
  defp persistence_target_argument(:multi, arguments), do: Enum.at(arguments, 2)

  defp query_targets_schema?({:from, _, [source | _rest]}, schemas, aliases, tainted) do
    source
    |> query_source()
    |> expression_targets_schema?(schemas, aliases, tainted)
  end

  defp query_targets_schema?(query, schemas, aliases, tainted) do
    expression_targets_schema?(query, schemas, aliases, tainted)
  end

  defp query_source({:in, _, [_binding, source]}), do: source
  defp query_source(source), do: source

  defp tainted_variables(ast, schemas, aliases) do
    Enum.reduce(1..5, MapSet.new(), fn _pass, tainted ->
      {_ast, next} = Macro.prewalk(ast, tainted, &taint_assignment(&1, &2, schemas, aliases))

      next
    end)
  end

  defp taint_assignment({:=, _, [left, right]} = node, tainted, schemas, aliases) do
    left_target? = assignment_targets_schema?(left, schemas, aliases, tainted)
    right_target? = assignment_targets_schema?(right, schemas, aliases, tainted)

    next =
      tainted
      |> maybe_taint(right_target?, variable_names(left))
      |> maybe_taint(left_target?, variable_names(right))

    {node, next}
  end

  defp taint_assignment(node, tainted, _schemas, _aliases), do: {node, tainted}

  defp maybe_taint(tainted, true, names), do: MapSet.union(tainted, names)
  defp maybe_taint(tainted, false, _names), do: tainted

  defp assignment_targets_schema?({:from, _, _arguments} = query, schemas, aliases, tainted) do
    query_targets_schema?(query, schemas, aliases, tainted)
  end

  defp assignment_targets_schema?(expression, schemas, aliases, tainted) do
    expression_targets_schema?(expression, schemas, aliases, tainted)
  end

  defp expression_targets_schema?(ast, schemas, aliases, tainted) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, segments} = node, found? ->
          modules = expanded_modules(segments, aliases)
          {node, found? or Enum.any?(modules, &(module_name(&1) in schemas))}

        {name, _, context} = node, found? when is_atom(name) and is_atom(context) ->
          {node, found? or MapSet.member?(tainted, name)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp variable_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, context} = node, names when is_atom(name) and is_atom(context) ->
          {node, MapSet.put(names, name)}

        node, names ->
          {node, names}
      end)

    names
  end

  defp ast_references_module?(ast, target, aliases) do
    target_parts = String.split(target, ".")

    alias_declares_target? =
      aliases
      |> Map.values()
      |> Enum.flat_map(& &1)
      |> Enum.any?(&(&1 == target_parts))

    {_ast, found?} =
      Macro.prewalk(ast, alias_declares_target?, fn
        {:__aliases__, _, segments} = node, found? ->
          {node, found? or target_parts in expanded_modules(segments, aliases)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp alias_bindings(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn node, aliases ->
        aliases =
          Enum.reduce(alias_targets(node), aliases, fn {local, target}, acc ->
            Map.update(acc, local, [target], &[target | &1])
          end)

        {node, aliases}
      end)

    aliases
  end

  defp alias_targets({:alias, _, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, children}]}) do
    for {:__aliases__, _, suffix} <- children do
      target = module_parts(prefix ++ suffix)
      {List.last(target), target}
    end
  end

  defp alias_targets({:alias, _, [{:__aliases__, _, segments}, opts]}) when is_list(opts) do
    target = module_parts(segments)

    local =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, as_segments} -> as_segments |> module_parts() |> List.last()
        _other -> List.last(target)
      end

    [{local, target}]
  end

  defp alias_targets({:alias, _, [{:__aliases__, _, segments}]}) do
    target = module_parts(segments)
    [{List.last(target), target}]
  end

  defp alias_targets(_node), do: []

  defp imported_modules(ast, aliases) do
    {_ast, imports} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:import, _, [{:__aliases__, _, segments} | _rest]} = node, imports ->
          modules = segments |> expanded_modules(aliases) |> Enum.map(&module_name/1)
          {node, Enum.reduce(modules, imports, &MapSet.put(&2, &1))}

        node, imports ->
          {node, imports}
      end)

    imports
  end

  defp expanded_modules(segments, aliases) do
    segments
    |> module_parts()
    |> expand_module_parts(aliases, MapSet.new())
    |> Enum.uniq()
  end

  defp module_ast_modules({:__aliases__, _, segments}, aliases), do: expanded_modules(segments, aliases)
  defp module_ast_modules(module, _aliases) when is_atom(module), do: [Module.split(module)]
  defp module_ast_modules(_module, _aliases), do: []

  defp expand_module_parts([], _aliases, _seen), do: []

  defp expand_module_parts([first | rest] = parts, aliases, seen) do
    if MapSet.member?(seen, parts) do
      [parts]
    else
      expanded =
        aliases
        |> Map.get(first, [])
        |> Enum.flat_map(&expand_module_parts(&1 ++ rest, aliases, MapSet.put(seen, parts)))

      [parts | expanded]
    end
  end

  defp repo_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Storyarn.Repo" or &1 == ["Repo"]))
  defp multi_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Ecto.Multi"))

  defp raw_sql_mutation?([sql | _rest]) when is_binary(sql) do
    Regex.match?(@sql_mutation_pattern, sql) or Regex.match?(@copy_from_pattern, sql)
  end

  defp raw_sql_mutation?([_dynamic | _rest]), do: true
  defp raw_sql_mutation?(_arguments), do: true

  defp raw_table_sql_mutation?([sql | _rest], literals) do
    case resolve_sql_literal(sql, literals) do
      {:known, value} -> table_sql_mutation?(value)
      :unknown -> true
    end
  end

  defp raw_table_sql_mutation?(_arguments, _literals), do: true

  defp sql_literals(ast) do
    {_ast, literals} =
      Macro.prewalk(ast, %{attributes: %{}, variables: %{}}, fn
        {:@, _, [{name, _, [value]}]} = node, literals when is_atom(name) ->
          resolved = resolve_sql_literal(value, literals)
          {node, put_sql_literal(literals, :attributes, name, resolved)}

        {:=, _, [{name, _, context}, value]} = node, literals
        when is_atom(name) and is_atom(context) ->
          resolved = resolve_sql_literal(value, literals)
          {node, put_sql_literal(literals, :variables, name, resolved)}

        node, literals ->
          {node, literals}
      end)

    literals
  end

  defp put_sql_literal(literals, namespace, name, resolved) do
    updated =
      literals
      |> Map.fetch!(namespace)
      |> Map.update(name, resolved, fn
        ^resolved -> resolved
        _other -> :unknown
      end)

    Map.put(literals, namespace, updated)
  end

  defp resolve_sql_literal(value, _literals) when is_binary(value), do: {:known, value}

  defp resolve_sql_literal({:__block__, _, [value]}, literals), do: resolve_sql_literal(value, literals)

  defp resolve_sql_literal({:@, _, [{name, _, _args}]}, literals) when is_atom(name) do
    Map.get(literals.attributes, name, :unknown)
  end

  defp resolve_sql_literal({name, _, context}, literals) when is_atom(name) and is_atom(context) do
    Map.get(literals.variables, name, :unknown)
  end

  defp resolve_sql_literal({:<>, _, [left, right]}, literals) do
    concat_sql_literals(resolve_sql_literal(left, literals), resolve_sql_literal(right, literals))
  end

  defp resolve_sql_literal({:<<>>, _, parts}, literals) do
    Enum.reduce_while(parts, {:known, ""}, fn part, {:known, acc} ->
      case resolve_sql_literal(part, literals) do
        {:known, value} -> {:cont, {:known, acc <> value}}
        :unknown -> {:halt, :unknown}
      end
    end)
  end

  defp resolve_sql_literal({sigil, _, [{:<<>>, _, parts}, modifiers]}, literals)
       when sigil in [:sigil_s, :sigil_S] and modifiers == [] do
    resolve_sql_literal({:<<>>, [], parts}, literals)
  end

  defp resolve_sql_literal(_value, _literals), do: :unknown

  defp concat_sql_literals({:known, left}, {:known, right}), do: {:known, left <> right}
  defp concat_sql_literals(_left, _right), do: :unknown

  defp table_sql_mutation?(source) do
    Regex.match?(@table_sql_mutation_pattern, source) or
      Regex.match?(@truncate_table_sql_mutation_pattern, source) or
      Regex.match?(@copy_from_table_pattern, source)
  end

  defp quoted!(source), do: Code.string_to_quoted!(source, columns: true)
  defp module_parts(segments), do: Enum.map(segments, &Atom.to_string/1)
  defp module_name(segments) when is_list(segments), do: Enum.join(module_parts_or_strings(segments), ".")
  defp module_parts_or_strings([part | _] = parts) when is_binary(part), do: parts
  defp module_parts_or_strings(parts), do: module_parts(parts)

  defp sha256(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp assert_metadata!(entry, keys) do
    for key <- keys do
      value = Map.fetch!(entry, key)
      assert is_atom(value) or (is_binary(value) and byte_size(value) > 0)
    end
  end
end
