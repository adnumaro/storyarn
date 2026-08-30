defmodule Storyarn.Architecture.SheetsVariableProjectionBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @policy_path "config/architecture_boundaries.exs"
  @projection_module "Storyarn.Sheets.References.Commands.VariableProjection"
  @projection_path "lib/storyarn/sheets/references/commands/variable_projection.ex"
  @references_module "Storyarn.Sheets.References"
  @references_path "lib/storyarn/sheets/references/references.ex"
  @sheet_snapshot_path "lib/storyarn/sheets/versioning/execution/sheet_snapshot.ex"
  @variable_reference_record "Storyarn.Sheets.References.Projections.VariableReferenceRecord"

  @repo_mutations ~w(insert insert! insert_all insert_or_update insert_or_update! update update! update_all delete delete! delete_all)a
  @raw_sql_functions ~w(query query!)a

  test "the Sheet restore projection remains insert-only and additive" do
    ast = @projection_path |> File.read!() |> Code.string_to_quoted!()
    aliases = alias_bindings(ast)

    refute imports_module?(ast, aliases, "Storyarn.Repo")
    refute imports_module?(ast, aliases, "Ecto.Multi")
    refute imports_module?(ast, aliases, "Ecto.Adapters.SQL")

    calls = remote_calls(ast, aliases)

    refute dynamic_persistence_call?(ast, aliases)

    repo_mutations =
      Enum.filter(calls, fn call ->
        call.module == "Storyarn.Repo" and
          (call.function in @repo_mutations or call.function == :dynamic)
      end)

    assert [insert] = repo_mutations
    assert insert.function == :insert_all
    assert [record_ast, _entries_ast, opts] = insert.args
    assert module_name(record_ast, aliases) == @variable_reference_record
    assert is_list(opts)
    assert Keyword.get(opts, :on_conflict) == :nothing

    multi_calls = Enum.filter(calls, &(&1.module == "Ecto.Multi"))

    raw_sql_calls =
      Enum.filter(calls, fn call ->
        call.module in ["Storyarn.Repo", "Ecto.Adapters.SQL"] and
          (call.function in @raw_sql_functions or call.function == :dynamic)
      end)

    assert multi_calls == [], "the additive projection must not build Ecto.Multi writes: #{inspect(multi_calls)}"
    assert raw_sql_calls == [], "the additive projection must not bypass Repo.insert_all: #{inspect(raw_sql_calls)}"
  end

  test "the privileged projection remains sealed behind SheetSnapshot" do
    entries = DependencyPolicy.load!(@policy_path).privileged_entrypoints

    assert %{
             path: @projection_path,
             functions: [rebuild_project: 1],
             allowed_callers: [@references_path]
           } = privileged_entry!(entries, @projection_module, rebuild_project: 1)

    assert %{
             path: @references_path,
             functions: [rebuild_project_variable_references: 1],
             allowed_callers: [@sheet_snapshot_path]
           } =
             privileged_entry!(
               entries,
               @references_module,
               rebuild_project_variable_references: 1
             )
  end

  defp privileged_entry!(entries, module, functions) do
    Enum.find(entries, &(&1.module == module and &1.functions == functions)) ||
      flunk("missing privileged entrypoint for #{module} #{inspect(functions)}")
  end

  defp remote_calls(ast, aliases) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {:apply, _, [module_ast, function_ast, args_ast]} = node, calls ->
          {node, [applied_call(module_ast, function_ast, args_ast, aliases) | calls]}

        {{:., _, [kernel_ast, :apply]}, _, [module_ast, function_ast, args_ast]} = node, calls ->
          if module_name(kernel_ast, aliases) == "Kernel" do
            {node, [applied_call(module_ast, function_ast, args_ast, aliases) | calls]}
          else
            {node, calls}
          end

        {{:., _, [module_ast, function]}, _, args} = node, calls
        when is_atom(function) and is_list(args) ->
          call = %{module: module_name(module_ast, aliases), function: function, args: args}
          {node, [call | calls]}

        node, calls ->
          {node, calls}
      end)

    calls
  end

  defp dynamic_persistence_call?(ast, aliases) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:apply, _, [module_ast, _function, _arguments]} = node, found? ->
          {node, found? or persistence_module?(module_name(module_ast, aliases))}

        {{:., _, [kernel_ast, :apply]}, _, [module_ast, _function, _arguments]} = node, found? ->
          kernel? = module_name(kernel_ast, aliases) == "Kernel"
          {node, found? or (kernel? and persistence_module?(module_name(module_ast, aliases)))}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp persistence_module?(module), do: module in ["Storyarn.Repo", "Ecto.Multi", "Ecto.Adapters.SQL"]

  defp applied_call(module_ast, function_ast, args_ast, aliases) do
    %{
      module: module_name(module_ast, aliases),
      function: literal_function(function_ast),
      args: literal_arguments(args_ast)
    }
  end

  defp literal_function(function) when is_atom(function), do: function
  defp literal_function(_function), do: :dynamic

  defp literal_arguments(arguments) when is_list(arguments), do: arguments
  defp literal_arguments(_arguments), do: :dynamic

  defp imports_module?(ast, aliases, target) do
    {_ast, imported?} =
      Macro.prewalk(ast, false, fn
        {:import, _, [module_ast | _opts]} = node, imported? ->
          {node, imported? or module_name(module_ast, aliases) == target}

        node, imported? ->
          {node, imported?}
      end)

    imported?
  end

  defp alias_bindings(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, segments}, opts]} = node, aliases when is_list(opts) ->
          local = alias_name(Keyword.get(opts, :as), segments)
          {node, Map.put(aliases, local, Enum.map(segments, &Atom.to_string/1))}

        {:alias, _, [{:__aliases__, _, segments}]} = node, aliases ->
          local = segments |> List.last() |> Atom.to_string()
          {node, Map.put(aliases, local, Enum.map(segments, &Atom.to_string/1))}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp alias_name({:__aliases__, _, segments}, _target_segments), do: segments |> List.last() |> Atom.to_string()

  defp alias_name(_as, target_segments), do: target_segments |> List.last() |> Atom.to_string()

  defp module_name({:__aliases__, _, [first | rest]}, aliases) do
    first = Atom.to_string(first)
    aliases |> Map.get(first, [first]) |> Kernel.++(Enum.map(rest, &Atom.to_string/1)) |> Enum.join(".")
  end

  defp module_name(module, _aliases) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp module_name(_module, _aliases), do: nil
end
