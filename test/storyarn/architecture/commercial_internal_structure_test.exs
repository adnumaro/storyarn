defmodule Storyarn.Architecture.CommercialInternalStructureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @root "lib/storyarn/commercial"
  @roles ~w(commands entities execution projections queries reference_data rules)
  @root_files ~w(billing.ex project_storage_reservations.ex subscription_crud.ex)
  @root_private_targets [
    "commands/",
    "entities/",
    "execution/",
    "projections/",
    "queries/storage_cleanup_ownership_receipt_record.ex",
    "queries/subscriptions.ex",
    "reference_data/",
    "rules/",
    "subscription_crud.ex"
  ]
  @passive_roles ~w(entities projections queries reference_data rules)
  @effectful_targets [
    "lib/storyarn/commercial.ex",
    "lib/storyarn/commercial/billing.ex",
    "lib/storyarn/commercial/project_storage_reservations.ex",
    "lib/storyarn/commercial/subscription_crud.ex",
    "lib/storyarn/commercial/commands/",
    "lib/storyarn/commercial/execution/"
  ]
  @forbidden_passive_role_edges [
    {"rules", "queries"},
    {"projections", "queries"},
    {"projections", "rules"},
    {"reference_data", "queries"},
    {"reference_data", "rules"},
    {"entities", "queries"}
  ]
  @repo_write_functions ~w(
    delete delete! delete_all insert insert! insert_all insert_or_update insert_or_update!
    update update! update_all
  )a
  @repo_orchestration_functions ~w(rollback transact transaction)a
  @repo_raw_sql_functions ~w(query query!)a
  @multi_write_functions ~w(
    all append delete delete_all error exists? insert insert_all insert_or_update merge one prepend
    put run update update_all
  )a
  @sql_mutation_pattern ~r/\b(?:INSERT\s+INTO|UPDATE(?:\s+ONLY)?|DELETE\s+FROM|MERGE\s+INTO|TRUNCATE(?:\s+TABLE)?|COPY\b[\s\S]*?\bFROM)\b/i

  test "Commercial has exactly the agreed role folders and stable internal facets" do
    assert directories_in(@root) == Enum.sort(@roles)

    root_files =
      @root
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    assert root_files == Enum.sort(@root_files)
  end

  test "generic persistence and shared folders cannot appear inside Commercial" do
    forbidden =
      @root
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&(File.dir?(&1) and Path.basename(&1) in ["persistence", "shared"]))

    assert forbidden == [],
           "Commercial uses owned projections and explicit roles, not generic folders: #{inspect(forbidden)}"
  end

  test "Commercial passive roles cannot perform writes or persistence orchestration" do
    passive_sources =
      Enum.flat_map(@passive_roles, fn role ->
        Path.wildcard(Path.join(@root, "#{role}/**/*.ex"))
      end)

    violations = Enum.filter(passive_sources, &persistence_mutation?(File.read!(&1)))

    assert passive_sources != []

    assert violations == [],
           "Commercial passive/read roles must not perform persistence writes: #{inspect(violations)}"
  end

  test "the passive-role write guard resolves aliases and avoids read-only false positives" do
    assert persistence_mutation?("alias Storyarn.Repo\nRepo.insert_or_update(changeset)")
    assert persistence_mutation?("alias Storyarn.Repo, as: Persistence\nPersistence.update(changeset)")
    assert persistence_mutation?("alias Storyarn.{Repo}\nRepo.delete(changeset)")

    assert persistence_mutation?(
             "alias Storyarn, as: Domain\nalias Domain.Repo, as: Persistence\n" <>
               "Persistence.insert(changeset)"
           )

    assert persistence_mutation?("import Storyarn.Repo\ninsert_or_update(changeset)")
    assert persistence_mutation?("apply(Storyarn.Repo, :update, [changeset])")
    assert persistence_mutation?("repo.update(changeset)")
    assert persistence_mutation?("apply(repo, :insert, [changeset])")
    assert persistence_mutation?("alias Ecto.Multi\nMulti.insert_or_update(multi, :row, changeset)")
    assert persistence_mutation?("import Ecto.Query\nfrom(row in Row, lock: \"FOR UPDATE\")")

    refute persistence_mutation?("alias Storyarn.Repo\nRepo.all(Query)")
    refute persistence_mutation?("alias Storyarn.Repo\nRepo.get_by(Row, id: 1)")
    refute persistence_mutation?("alias Storyarn.Repo\nRepo.query!(\"SELECT 1\")")
    refute persistence_mutation?("alias Ecto.Multi\nMulti.new()")
    refute persistence_mutation?("Ecto.Changeset.update_change(changeset, :name, &String.trim/1)")
    refute persistence_mutation?("alias Another.Repo\nRepo.update(value)")
    refute persistence_mutation?("import Storyarn.Repo, only: [all: 1]\nall(Query)")
  end

  test "deterministic Commercial rules cannot access persistence or query construction" do
    rule_sources = Path.wildcard(Path.join(@root, "rules/**/*.ex"))
    violations = Enum.filter(rule_sources, &persistence_dependency?(File.read!(&1)))

    assert rule_sources != []
    assert violations == [], "Commercial rules must remain persistence-free: #{inspect(violations)}"
  end

  test "every projection and reference-data module documents its passive purpose" do
    sources =
      Enum.flat_map(~w(projections reference_data), fn role ->
        Path.wildcard(Path.join(@root, "#{role}/**/*.ex"))
      end)

    violations =
      Enum.reject(sources, fn path ->
        source = File.read!(path)
        source =~ "@moduledoc" and not (source =~ "@moduledoc false")
      end)

    assert sources != []
    assert violations == [], "Commercial passive-data semantics must be explicit: #{inspect(violations)}"
  end

  test "Commercial projections cannot acquire ordinary changeset behavior" do
    projection_sources = Path.wildcard(Path.join(@root, "projections/**/*.ex"))
    violations = Enum.filter(projection_sources, &changeset_dependency?(File.read!(&1)))

    assert projection_sources != []
    assert violations == [], "Commercial projections must remain read-only mappings: #{inspect(violations)}"
  end

  test "the ratchet keeps the bounded-context facade out of private implementation roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    Enum.each(@root_private_targets, fn private_target ->
      assert denial?(
               policy,
               "lib/storyarn/commercial.ex",
               "#{@root}/#{private_target}"
             ),
             "missing Commercial root-facade denial to #{private_target}"
    end)
  end

  test "the ratchet keeps every Commercial passive role out of effectful workflows and facades" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for source_role <- @passive_roles, target_root <- @effectful_targets do
      source_root = "#{@root}/#{source_role}/"

      assert denial?(policy, source_root, target_root),
             "missing Commercial passive-role denial from #{source_root} to #{target_root}"
    end
  end

  test "the ratchet preserves direction between Commercial passive roles" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    for {source_role, target_role} <- @forbidden_passive_role_edges do
      assert denial?(
               policy,
               "#{@root}/#{source_role}/",
               "#{@root}/#{target_role}/"
             ),
             "missing Commercial passive-role denial for #{source_role} -> #{target_role}"
    end
  end

  test "the ratchet keeps deterministic Commercial rules away from Repo" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert denial?(policy, "#{@root}/rules/", "lib/storyarn/repo.ex")
  end

  test "production consumers enter Commercial only through its root facade" do
    sources =
      Enum.reject(Path.wildcard("lib/storyarn/**/*.ex") ++ Path.wildcard("lib/storyarn_web/**/*.ex"), fn path ->
        String.starts_with?(path, "lib/storyarn/commercial")
      end)

    violations =
      sources
      |> Enum.flat_map(&internal_commercial_references/1)
      |> Enum.sort()

    assert violations == [],
           "production consumers must call Storyarn.Commercial, not its internals: #{inspect(violations)}"
  end

  test "the consumer scanner resolves root and grouped Commercial aliases" do
    assert internal_commercial_references_in_source(
             "alias Storyarn.Commercial\nCommercial.Billing.default_plan()",
             "fixture.ex"
           ) != []

    assert internal_commercial_references_in_source(
             "alias Storyarn.Commercial.{Billing}\nBilling.default_plan()",
             "fixture.ex"
           ) != []

    assert internal_commercial_references_in_source(
             "alias Storyarn.Commercial.Billing, as: Plans\nPlans.default_plan()",
             "fixture.ex"
           ) != []

    assert internal_commercial_references_in_source(
             "alias Storyarn.Commercial\nCommercial.default_plan()",
             "fixture.ex"
           ) == []
  end

  defp directories_in(root) do
    root
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp denial?(policy, source_root, target_root) do
    Enum.any?(policy.path_denials, fn denial ->
      denial.source_root == source_root and denial.target_root == target_root and
        denial.kinds == ["runtime", "export", "compile"]
    end)
  end

  defp persistence_mutation?(source) do
    ast = Code.string_to_quoted!(source, columns: true)
    aliases = alias_bindings(ast)
    imports = import_bindings(ast, aliases)

    {_ast, mutation?} =
      Macro.prewalk(ast, false, fn node, mutation? ->
        {node, mutation? or persistence_mutation_node?(node, aliases, imports)}
      end)

    mutation?
  end

  defp persistence_dependency?(source) do
    ast = Code.string_to_quoted!(source, columns: true)
    aliases = alias_bindings(ast)

    {_ast, persistence?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, segments} = node, persistence? ->
          modules = expanded_modules(segments, aliases)

          {node, persistence? or repo_module?(modules) or multi_module?(modules) or query_module?(modules)}

        {{:., _, [{:repo, _, context}, _function]}, _, _arguments} = node, _persistence?
        when is_atom(context) ->
          {node, true}

        node, persistence? ->
          {node, persistence?}
      end)

    persistence?
  end

  defp changeset_dependency?(source) do
    ast = Code.string_to_quoted!(source, columns: true)
    aliases = alias_bindings(ast)

    {_ast, changeset?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, segments} = node, changeset? ->
          modules = expanded_modules(segments, aliases)
          {node, changeset? or Enum.any?(modules, &(module_name(&1) == "Ecto.Changeset"))}

        node, changeset? ->
          {node, changeset?}
      end)

    changeset?
  end

  defp persistence_mutation_node?(
         {{:., _, [kernel_ast, :apply]}, _, [module_ast, function, arguments]},
         aliases,
         _imports
       )
       when is_atom(function) and is_list(arguments) do
    kernel_ast
    |> module_ast_modules(aliases)
    |> kernel_module?()
    |> then(fn kernel? ->
      kernel? and persistence_module_call?(module_ast_modules(module_ast, aliases), function, arguments)
    end)
  end

  defp persistence_mutation_node?({:apply, _, [module_ast, function, arguments]}, aliases, _imports)
       when is_atom(function) and is_list(arguments) do
    (dynamic_repo_receiver?(module_ast) and repo_call?(function, arguments)) or
      persistence_module_call?(module_ast_modules(module_ast, aliases), function, arguments)
  end

  defp persistence_mutation_node?({{:., _, [module_ast, function]}, _, arguments}, aliases, _imports)
       when is_atom(function) and is_list(arguments) do
    (dynamic_repo_receiver?(module_ast) and repo_call?(function, arguments)) or
      persistence_module_call?(module_ast_modules(module_ast, aliases), function, arguments)
  end

  defp persistence_mutation_node?({function, _, arguments}, _aliases, imports)
       when is_atom(function) and is_list(arguments) do
    arity = length(arguments)

    cond do
      imported?(imports, "Storyarn.Repo", function, arity) ->
        repo_call?(function, arguments)

      imported?(imports, "Ecto.Multi", function, arity) ->
        function in @multi_write_functions

      imported?(imports, "Ecto.Query", function, arity, :macro) ->
        query_lock_call?(function, arguments)

      true ->
        false
    end
  end

  defp persistence_mutation_node?(_node, _aliases, _imports), do: false

  defp persistence_module_call?(modules, function, arguments) do
    cond do
      repo_module?(modules) -> repo_call?(function, arguments)
      multi_module?(modules) -> function in @multi_write_functions
      query_module?(modules) -> query_lock_call?(function, arguments)
      true -> false
    end
  end

  defp repo_call?(function, _arguments)
       when function in @repo_write_functions or function in @repo_orchestration_functions, do: true

  defp repo_call?(function, arguments) when function in @repo_raw_sql_functions, do: raw_sql_mutation?(arguments)

  defp repo_call?(_function, _arguments), do: false

  defp query_lock_call?(:lock, _arguments), do: true
  defp query_lock_call?(:from, arguments), do: contains_lock_option?(arguments)
  defp query_lock_call?(_function, _arguments), do: false

  defp contains_lock_option?(ast) do
    {_ast, lock?} =
      Macro.prewalk(ast, false, fn
        {:lock, _value} = node, _lock? -> {node, true}
        node, lock? -> {node, lock?}
      end)

    lock?
  end

  defp raw_sql_mutation?([sql | _arguments]) when is_binary(sql), do: Regex.match?(@sql_mutation_pattern, sql)

  # A dynamic raw query cannot prove that the passive role remains read-only.
  defp raw_sql_mutation?([_dynamic_sql | _arguments]), do: true
  defp raw_sql_mutation?(_arguments), do: true

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

  defp alias_targets({:alias, meta, [{{:., _, [{:__aliases__, _, _prefix}, :{}]}, _, _children} = grouped, opts]})
       when is_list(opts), do: alias_targets({:alias, meta, [grouped]})

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

  defp import_bindings(ast, aliases) do
    {_ast, imports} =
      Macro.prewalk(ast, %{}, fn
        {:import, _, [module_ast | rest]} = node, imports ->
          opts = if match?([opts] when is_list(opts), rest), do: hd(rest), else: []

          imports =
            module_ast
            |> module_ast_modules(aliases)
            |> Enum.reduce(imports, fn module, acc ->
              Map.update(acc, module_name(module), [opts], &[opts | &1])
            end)

          {node, imports}

        node, imports ->
          {node, imports}
      end)

    imports
  end

  defp imported?(imports, module, function, arity, kind \\ :function) do
    imports
    |> Map.get(module, [])
    |> Enum.any?(&import_allows?(&1, function, arity, kind))
  end

  defp import_allows?(opts, function, arity, kind) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    allowed? =
      case only do
        nil -> true
        :functions -> kind == :function
        :macros -> kind == :macro
        entries when is_list(entries) -> {function, arity} in entries
        _other -> false
      end

    allowed? and {function, arity} not in except
  end

  defp module_ast_modules({:__aliases__, _, segments}, aliases), do: expanded_modules(segments, aliases)

  defp module_ast_modules(module, _aliases) when is_atom(module) do
    parts =
      module
      |> Atom.to_string()
      |> String.trim_leading("Elixir.")
      |> String.split(".")

    [parts]
  end

  defp module_ast_modules(_module, _aliases), do: []

  defp expanded_modules(segments, aliases) do
    segments
    |> module_parts()
    |> expand_module_parts(aliases, MapSet.new())
    |> Enum.uniq()
  end

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

  defp repo_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Storyarn.Repo"))
  defp multi_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Ecto.Multi"))
  defp query_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Ecto.Query"))
  defp kernel_module?(modules), do: Enum.any?(modules, &(module_name(&1) == "Kernel"))

  defp dynamic_repo_receiver?({name, _meta, context}) when is_atom(name) and is_atom(context) do
    name in [:repo, :repository, :database, :persistence] or String.ends_with?(Atom.to_string(name), "_repo")
  end

  defp dynamic_repo_receiver?(_module_ast), do: false

  defp module_parts(segments), do: Enum.map(segments, &Atom.to_string/1)
  defp module_name(segments), do: Enum.join(segments, ".")

  defp internal_commercial_references(path) do
    path
    |> File.read!()
    |> internal_commercial_references_in_source(path)
  end

  defp internal_commercial_references_in_source(source, path) do
    ast = Code.string_to_quoted!(source, file: path, columns: true)
    aliases = alias_bindings(ast)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, segments} = node, acc ->
          references =
            segments
            |> expanded_modules(aliases)
            |> Enum.filter(&commercial_internal_module?/1)
            |> Enum.map(fn module -> "#{path}:#{meta[:line] || 1}: #{module_name(module)}" end)

          {node, references ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(references)
  end

  defp commercial_internal_module?(["Storyarn", "Commercial", _internal | _rest]), do: true
  defp commercial_internal_module?(_module), do: false
end
