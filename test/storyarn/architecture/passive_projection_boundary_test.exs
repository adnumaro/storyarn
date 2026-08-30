defmodule Storyarn.Architecture.PassiveProjectionBoundaryTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 120_000

  @projection_glob "lib/storyarn/**/projections/**/*.ex"

  @repo_write_functions ~w(
    delete delete! delete_all insert insert! insert_all insert_or_update
    insert_or_update! update update! update_all
  )a
  @repo_transaction_functions ~w(checkout rollback transact transaction)a
  @raw_sql_functions ~w(query query! query_many query_many!)a
  @multi_write_functions ~w(
    append delete delete_all error insert insert_all insert_or_update merge prepend
    put run update update_all
  )a

  test "consumer-owned projections remain structurally read-only" do
    projection_paths = projection_paths()
    ecto_mapping_paths = Enum.filter(projection_paths, &ecto_mapping?/1)

    assert projection_paths != [], "the projection guard must never pass over an empty file set"

    assert ecto_mapping_paths != [],
           "the projection guard must discover the production Ecto read mappings"

    violations =
      projection_paths
      |> Enum.flat_map(fn path -> path |> File.read!() |> analyze_source(path) end)
      |> sort_violations()

    assert violations == [], """
    Files under projections/ are consumer-owned, passive read mappings. They may
    describe foreign tables and associations, but must not expose changesets,
    mutate through Repo/Ecto.Multi/raw SQL, or acquire transaction locks.

    Move owned writable mappings to records/ and cross-context intent to the
    owning context's public command port.

    Violations: #{inspect(violations, pretty: true)}
    """
  end

  test "the guard detects aliases, imports, captures, and dynamic persistence calls" do
    source = ~S"""
    defmodule ExampleProjection do
      alias Storyarn.Repo, as: Database
      alias Ecto.{Changeset, Multi}
      import Storyarn.Repo, only: [delete!: 1]

      @repo Storyarn.Repo

      def changeset(record, attrs), do: Changeset.cast(record, attrs, [:name])
      def insert(record), do: @repo.insert(record)
      def delete(record), do: delete!(record)
      def update_later, do: &Database.update/1

      def queue(multi, changeset) do
        Multi.update(multi, :projection, changeset)
      end

      def dynamic(operation, arguments), do: apply(Database, operation, arguments)
      def dynamic_attribute(operation, arguments), do: Kernel.apply(@repo, operation, arguments)
    end
    """

    violations = analyze_source(source, "fixture_projection.ex")

    assert_violation(violations, :changeset_definition, :changeset)
    assert_violation(violations, :changeset_write, :cast)
    assert_violation(violations, :repo_write, :insert)
    assert_violation(violations, :repo_write, :delete!)
    assert_violation(violations, :repo_write, :update)
    assert_violation(violations, :multi_write, :update)
    assert_violation(violations, :dynamic_persistence_call, :dynamic)

    assert Enum.count(violations, &(&1.kind == :dynamic_persistence_call)) == 2
  end

  test "the guard detects transactions, query locks, and raw SQL mutations" do
    source = ~S"""
    defmodule ExampleProjection do
      import Ecto.Query, only: [from: 2, lock: 2]
      alias Ecto.Adapters.SQL, as: SQL
      alias Storyarn.Repo

      def locked(record), do: from(item in record, lock: "FOR UPDATE")
      def shared(query), do: lock(query, "FOR SHARE")
      def transaction(fun), do: Repo.transaction(fun)
      def raw_update(params), do: Repo.query!("UPDATE projects SET name = $1", params)

      def raw_delete(params) do
        SQL.query(Repo, "WITH doomed AS (SELECT id FROM projects) DELETE FROM projects", params)
      end

      def dynamic_sql(sql), do: SQL.query!(Repo, sql, [])
      def raw_lock, do: Repo.query!("SELECT id FROM projects FOR NO KEY UPDATE")
    end
    """

    violations = analyze_source(source, "fixture_projection.ex")

    assert_violation(violations, :query_lock, :lock)
    assert_violation(violations, :transaction, :transaction)
    assert_violation(violations, :raw_sql_write, :query!)
    assert_violation(violations, :raw_sql_write, :query)
    assert_violation(violations, :dynamic_raw_sql, :query!)
    assert_violation(violations, :raw_sql_lock, :query!)

    assert Enum.count(violations, &(&1.kind == :query_lock)) == 2
  end

  test "the guard accounts for the implicit first argument in explicitly imported pipes" do
    source = ~S"""
    defmodule ExampleProjection do
      import Storyarn.Repo, only: [update: 1]

      def persist(record), do: record |> update()
    end
    """

    violations = analyze_source(source, "fixture_imported_pipe.ex")

    assert Enum.count(violations, &(&1.kind == :repo_write and &1.operation == :update)) == 1
  end

  test "read-only Ecto queries and raw SELECT statements are not false positives" do
    source = ~S"""
    defmodule ExampleProjection do
      import Ecto.Query
      alias Ecto.Adapters.SQL
      alias Storyarn.Repo

      def by_id(id), do: Repo.one(from(item in "projects", where: item.id == ^id))
      def all, do: Repo.all("projects")

      def selected do
        Repo.query!("SELECT id, updated_at FROM projects WHERE deleted_at IS NULL")
      end

      def selected_with_cte do
        SQL.query(
          Repo,
          "WITH visible AS (SELECT id FROM projects) SELECT id FROM visible",
          []
        )
      end

      def selected_from_pipe do
        "SELECT 'UPDATE is text, not a statement' AS note" |> Repo.query!()
      end
    end
    """

    assert analyze_source(source, "fixture_reader.ex") == []
  end

  defp projection_paths do
    @projection_glob
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  defp ecto_mapping?(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!()
    |> contains_ecto_schema?()
  end

  defp contains_ecto_schema?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, [:Ecto, :Schema]} | _]} = node, _found? ->
          {node, true}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp analyze_source(source, path) do
    ast = Code.string_to_quoted!(source)
    aliases = alias_bindings(ast)
    attributes = module_attribute_bindings(ast, aliases)
    imports = import_bindings(ast, aliases)
    context = %{aliases: aliases, attributes: attributes, imports: imports, path: path}

    {_ast, violations} =
      Macro.prewalk(ast, [], fn node, violations ->
        {node, detect_node(node, context, violations)}
      end)

    violations
    |> Enum.uniq()
    |> sort_violations()
  end

  defp detect_node({definition, meta, [head | _]} = _node, context, violations)
       when definition in [:def, :defp, :defdelegate, :defmacro, :defmacrop] do
    case defined_function_name(head) do
      function when is_atom(function) ->
        if function |> Atom.to_string() |> String.contains?("changeset") do
          [violation(context, meta, :changeset_definition, function) | violations]
        else
          violations
        end

      _other ->
        violations
    end
  end

  defp detect_node({:|>, meta, [sql_ast, {{:., _, [module_ast, function]}, _, args}]}, context, violations)
       when function in @raw_sql_functions and is_list(args) do
    module = module_name(module_ast, context)
    classify_call(module, function, [sql_ast | args], meta, context, violations)
  end

  defp detect_node({:|>, meta, [sql_ast, {function, _, args}]}, context, violations)
       when function in @raw_sql_functions and is_list(args) do
    context.imports
    |> imported_modules(function, length(args) + 1)
    |> Enum.reduce(violations, fn module, acc ->
      classify_call(module, function, [sql_ast | args], meta, context, acc)
    end)
  end

  defp detect_node({:|>, meta, [left, {function, _, args}]}, context, violations)
       when is_atom(function) and is_list(args) do
    context.imports
    |> imported_modules(function, length(args) + 1)
    |> Enum.reduce(violations, fn module, acc ->
      classify_call(module, function, [left | args], meta, context, acc)
    end)
  end

  # The enclosing pipe clause above supplies the SQL argument. Macro.prewalk/3
  # will subsequently visit this zero-argument RHS on its own; ignoring that
  # second visit prevents a literal piped SELECT from looking dynamic.
  defp detect_node({{:., _, [_module_ast, function]}, _, []}, _context, violations) when function in @raw_sql_functions,
    do: violations

  defp detect_node({function, _, []}, _context, violations) when function in @raw_sql_functions, do: violations

  defp detect_node({:apply, meta, [module_ast, function_ast, arguments_ast]}, context, violations) do
    classify_apply(module_ast, function_ast, arguments_ast, meta, context, violations)
  end

  defp detect_node({{:., meta, [kernel_ast, :apply]}, _, [module_ast, function_ast, arguments_ast]}, context, violations) do
    if module_name(kernel_ast, context) == "Kernel" do
      classify_apply(module_ast, function_ast, arguments_ast, meta, context, violations)
    else
      violations
    end
  end

  defp detect_node({{:., meta, [module_ast, function]}, _, args}, context, violations)
       when is_atom(function) and is_list(args) do
    classify_call(
      module_name(module_ast, context),
      function,
      args,
      meta,
      context,
      violations
    )
  end

  defp detect_node({function, meta, args}, context, violations)
       when is_atom(function) and (is_list(args) or is_nil(args)) do
    arity = if is_list(args), do: length(args), else: :unknown

    context.imports
    |> imported_modules(function, arity)
    |> Enum.reduce(violations, fn module, acc ->
      classify_call(module, function, args || [], meta, context, acc)
    end)
  end

  defp detect_node({:lock, _value} = node, context, violations) do
    [violation(context, node, :query_lock, :lock) | violations]
  end

  defp detect_node(_node, _context, violations), do: violations

  defp classify_apply(module_ast, function_ast, arguments_ast, meta, context, violations) do
    module = module_name(module_ast, context)

    case literal_function(function_ast) do
      :dynamic ->
        if persistence_module?(module) do
          [violation(context, meta, :dynamic_persistence_call, :dynamic, module) | violations]
        else
          violations
        end

      function ->
        arguments = if is_list(arguments_ast), do: arguments_ast, else: []
        classify_call(module, function, arguments, meta, context, violations)
    end
  end

  defp classify_call("Storyarn.Repo" = module, function, _args, meta, context, violations)
       when function in @repo_write_functions do
    [violation(context, meta, :repo_write, function, module) | violations]
  end

  defp classify_call("Storyarn.Repo" = module, function, _args, meta, context, violations)
       when function in @repo_transaction_functions do
    [violation(context, meta, :transaction, function, module) | violations]
  end

  defp classify_call("Storyarn.Repo" = module, function, args, meta, context, violations)
       when function in @raw_sql_functions do
    classify_raw_sql(module, function, args, meta, context, violations)
  end

  defp classify_call("Ecto.Adapters.SQL" = module, function, args, meta, context, violations)
       when function in @raw_sql_functions do
    classify_raw_sql(module, function, args, meta, context, violations)
  end

  defp classify_call("Ecto.Multi" = module, function, _args, meta, context, violations)
       when function in @multi_write_functions do
    [violation(context, meta, :multi_write, function, module) | violations]
  end

  defp classify_call("Ecto.Changeset" = module, function, _args, meta, context, violations) do
    [violation(context, meta, :changeset_write, function, module) | violations]
  end

  defp classify_call("Ecto.Query" = module, :lock, _args, meta, context, violations) do
    [violation(context, meta, :query_lock, :lock, module) | violations]
  end

  defp classify_call(_module, _function, _args, _meta, _context, violations), do: violations

  defp classify_raw_sql(module, function, args, meta, context, violations) do
    sql_position = if module == "Storyarn.Repo", do: 0, else: 1

    case args |> Enum.at(sql_position) |> literal_string() do
      {:ok, sql} ->
        cond do
          raw_sql_lock?(sql) ->
            [violation(context, meta, :raw_sql_lock, function, module) | violations]

          raw_sql_write?(sql) ->
            [violation(context, meta, :raw_sql_write, function, module) | violations]

          true ->
            violations
        end

      :dynamic ->
        [violation(context, meta, :dynamic_raw_sql, function, module) | violations]
    end
  end

  defp raw_sql_lock?(sql) do
    sql = normalize_sql(sql)

    Regex.match?(
      ~r/\bFOR\s+(?:NO\s+KEY\s+UPDATE|KEY\s+SHARE|UPDATE|SHARE)\b|\bLOCK\s+(?:TABLE\s+)?|\bPG_(?:TRY_)?ADVISORY_(?:XACT_)?LOCK(?:_SHARED)?\s*\(/,
      sql
    )
  end

  defp raw_sql_write?(sql) do
    sql = normalize_sql(sql)

    Regex.match?(
      ~r/\b(?:ALTER|CALL|COMMENT|COPY|CREATE|DELETE|DO|DROP|GRANT|INSERT|MERGE|REFRESH|REINDEX|REPLACE|REVOKE|TRUNCATE|UPDATE|UPSERT|VACUUM)\b/,
      sql
    )
  end

  defp normalize_sql(sql) do
    sql
    |> then(&Regex.replace(~r/\$[A-Za-z_][A-Za-z0-9_]*\$.*?\$[A-Za-z_][A-Za-z0-9_]*\$/s, &1, " "))
    |> then(&Regex.replace(~r/\$\$.*?\$\$/s, &1, " "))
    |> then(&Regex.replace(~r/'(?:''|[^'])*'/s, &1, " "))
    |> then(&Regex.replace(~r/"(?:""|[^"])*"/s, &1, " "))
    |> then(&Regex.replace(~r/\/\*.*?\*\//s, &1, " "))
    |> then(&Regex.replace(~r/--[^\r\n]*/, &1, " "))
    |> String.upcase()
  end

  defp literal_string(value) when is_binary(value), do: {:ok, value}

  defp literal_string({:<>, _, [left, right]}) do
    with {:ok, left} <- literal_string(left),
         {:ok, right} <- literal_string(right) do
      {:ok, left <> right}
    end
  end

  defp literal_string({sigil, _, [{:<<>>, _, parts}, modifiers]})
       when sigil in [:sigil_s, :sigil_S] and is_list(parts) and is_list(modifiers) do
    if Enum.all?(parts, &is_binary/1), do: {:ok, Enum.join(parts)}, else: :dynamic
  end

  defp literal_string(_value), do: :dynamic

  defp alias_bindings(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{{:., _, [base_ast, :{}]}, _, nested_modules}]} = node, aliases ->
          base = raw_module_segments(base_ast)

          aliases =
            Enum.reduce(nested_modules, aliases, fn nested_ast, acc ->
              segments = base ++ raw_module_segments(nested_ast)
              Map.put(acc, List.last(segments), segments)
            end)

          {node, aliases}

        {:alias, _, [module_ast, opts]} = node, aliases when is_list(opts) ->
          segments = raw_module_segments(module_ast)
          local = alias_local_name(Keyword.get(opts, :as), segments)
          {node, put_alias(aliases, local, segments)}

        {:alias, _, [module_ast]} = node, aliases ->
          segments = raw_module_segments(module_ast)
          {node, put_alias(aliases, List.last(segments), segments)}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp module_attribute_bindings(ast, aliases) do
    context = %{aliases: aliases, attributes: %{}}

    {_ast, attributes} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [module_ast]}]} = node, attributes when is_atom(name) ->
          module = module_name(module_ast, %{context | attributes: attributes})

          if is_binary(module) do
            {node, Map.put(attributes, name, module)}
          else
            {node, attributes}
          end

        node, attributes ->
          {node, attributes}
      end)

    attributes
  end

  defp import_bindings(ast, aliases) do
    context = %{aliases: aliases, attributes: %{}}

    {_ast, imports} =
      Macro.prewalk(ast, [], fn
        {:import, _, [module_ast, opts]} = node, imports when is_list(opts) ->
          binding = import_binding(module_name(module_ast, context), opts)
          {node, [binding | imports]}

        {:import, _, [module_ast]} = node, imports ->
          binding = import_binding(module_name(module_ast, context), [])
          {node, [binding | imports]}

        node, imports ->
          {node, imports}
      end)

    imports
  end

  defp import_binding(module, opts) do
    %{module: module, only: import_filter(opts[:only]), except: import_filter(opts[:except])}
  end

  defp import_filter(entries) when is_list(entries), do: MapSet.new(entries)
  defp import_filter(_entries), do: nil

  defp imported_modules(imports, function, arity) do
    imports
    |> Enum.filter(&imported?(&1, function, arity))
    |> Enum.map(& &1.module)
    |> Enum.filter(&persistence_module?/1)
    |> Enum.uniq()
  end

  defp imported?(binding, function, arity) do
    possible_arities = if arity == :unknown, do: :unknown, else: [arity]

    included? =
      is_nil(binding.only) or possible_arities == :unknown or
        Enum.any?(possible_arities, &MapSet.member?(binding.only, {function, &1}))

    excluded? =
      not is_nil(binding.except) and possible_arities != :unknown and
        Enum.any?(possible_arities, &MapSet.member?(binding.except, {function, &1}))

    included? and not excluded?
  end

  defp module_name({:__aliases__, _, [first | rest]}, context) do
    first = Atom.to_string(first)
    segments = Map.get(context.aliases, first, [first]) ++ Enum.map(rest, &Atom.to_string/1)
    Enum.join(segments, ".")
  end

  defp module_name({:@, _, [{name, _, _}]}, context) when is_atom(name) do
    Map.get(context.attributes, name)
  end

  defp module_name(module, _context) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name(_module, _context), do: nil

  defp raw_module_segments({:__aliases__, _, segments}), do: Enum.map(segments, &Atom.to_string/1)

  defp raw_module_segments(_module), do: []

  defp alias_local_name({:__aliases__, _, segments}, _target_segments), do: segments |> List.last() |> Atom.to_string()

  defp alias_local_name(_as, target_segments), do: List.last(target_segments)

  defp put_alias(aliases, local, segments) when is_binary(local) and is_list(segments) and segments != [],
    do: Map.put(aliases, local, segments)

  defp put_alias(aliases, _local, _segments), do: aliases

  defp defined_function_name({:when, _, [head | _guards]}), do: defined_function_name(head)
  defp defined_function_name({name, _, _args}) when is_atom(name), do: name
  defp defined_function_name(_head), do: nil

  defp literal_function(function) when is_atom(function), do: function
  defp literal_function(_function), do: :dynamic

  defp persistence_module?(module),
    do: module in ["Storyarn.Repo", "Ecto.Multi", "Ecto.Changeset", "Ecto.Query", "Ecto.Adapters.SQL"]

  defp violation(context, metadata, kind, operation, module \\ nil) do
    %{
      path: context.path,
      line: metadata_line(metadata),
      kind: kind,
      operation: operation,
      module: module
    }
  end

  defp metadata_line(metadata) when is_list(metadata), do: Keyword.get(metadata, :line, 0)
  defp metadata_line({_key, metadata}) when is_list(metadata), do: Keyword.get(metadata, :line, 0)
  defp metadata_line(_metadata), do: 0

  defp sort_violations(violations) do
    Enum.sort_by(violations, &{&1.path, &1.line, &1.kind, &1.operation, &1.module})
  end

  defp assert_violation(violations, kind, operation) do
    assert Enum.any?(violations, &(&1.kind == kind and &1.operation == operation)), """
    expected #{inspect(kind)} #{inspect(operation)} in:
    #{inspect(violations, pretty: true)}
    """
  end
end
