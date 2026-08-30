defmodule Storyarn.Architecture.PrivilegedEntrypointBoundaryTest do
  use ExUnit.Case, async: false

  alias Storyarn.Architecture.DependencyPolicy

  @moduletag timeout: 120_000

  @policy_path "config/architecture_boundaries.exs"
  @storyarn_root "lib"
  @eng103_write_port_entrypoints MapSet.new([
                                   {"Storyarn.Sheets.Editor.Adapters.Flows.DialogueAudio", [assign: 4]},
                                   {"Storyarn.Flows", [assign_dialogue_audio: 4]},
                                   {"Storyarn.Flows.Editor", [assign_dialogue_audio: 4]},
                                   {"Storyarn.Flows.Editor.Commands.DialogueAudio", [assign: 4]},
                                   {"Storyarn.Projects.References.Adapters.Flows.StaleVariableReferenceRepair",
                                    [repair_project: 2]},
                                   {"Storyarn.Flows", [repair_stale_variable_references: 2]},
                                   {"Storyarn.Flows.References", [repair_stale_variable_references: 2]},
                                   {"Storyarn.Flows.References.Commands.StaleVariableReferenceRepair",
                                    [repair_project: 2]}
                                 ])

  test "privileged materialization and restore entrypoints keep their exact reviewed callers" do
    entries = policy().privileged_entrypoints
    sources = parsed_sources()

    assert length(entries) == 64
    assert Enum.uniq_by(entries, &entry_identity/1) == entries
    assert disjoint_function_scopes?(entries)

    assert unreviewed_public_wrappers(entries, sources) == [], """
    A public function in a privileged target module reaches a reviewed
    function-scoped entrypoint without being declared as an entrypoint itself.

    Declare the wrapper explicitly with its exact callers, or keep the helper
    private so the reviewed entrypoint remains the only public route.
    """

    for entry <- entries do
      assert File.regular?(entry.path), "privileged entrypoint path is missing: #{entry.path}"
      assert byte_size(entry.reason) > 0
      assert valid_function_scope?(entry.functions)
      assert entry.allowed_callers == entry.allowed_callers |> Enum.uniq() |> Enum.sort()

      for caller <- entry.allowed_callers do
        assert File.regular?(caller), "privileged entrypoint caller is missing: #{caller}"
      end

      actual_callers = entrypoint_callers(entry, sources)

      assert actual_callers == entry.allowed_callers, """
      #{entry.module} #{function_scope_label(entry.functions)} may only be reached
      by its explicitly reviewed coordinator paths.

      Actual: #{inspect(actual_callers, pretty: true)}
      Expected: #{inspect(entry.allowed_callers, pretty: true)}
      """
    end
  end

  test "ENG-103 cross-context write ports remain sealed at every public hop" do
    entrypoints = MapSet.new(policy().privileged_entrypoints, &entry_identity/1)

    assert MapSet.subset?(@eng103_write_port_entrypoints, entrypoints)
  end

  test "AST analysis catches supported aliases, captures, delegates, pipes and apply calls" do
    module_entry = %{
      module: "Storyarn.Projects.Versioning.ProjectRecovery",
      functions: :all
    }

    restore_entry = %{
      module: "Storyarn.Flows.Versioning.FlowSnapshot",
      functions: [restore: 2, restore: 3]
    }

    sheet_projection_entry = %{
      module: "Storyarn.Sheets.References.Commands.VariableProjection",
      functions: [rebuild_project: 1]
    }

    project_reference_entry = %{
      module: "Storyarn.Projects.References",
      functions: [rebuild_project_entity_references: 1]
    }

    assert entrypoint_used?(
             "alias Storyarn.Projects.Versioning.ProjectRecovery\n" <>
               "Keyword.get(opts, :recovery, ProjectRecovery)",
             module_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Projects.Versioning.{ProjectRecovery, ProjectSnapshotBuilder}\n" <>
               "ProjectRecovery.materialize_template(1, %{}, 2, [])",
             module_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Projects.Versioning.ProjectRecovery, as: Recovery\n" <>
               "&Recovery.materialize_snapshot_import/4",
             module_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning, as: Versioning\n" <>
               "Versioning.FlowSnapshot.restore(flow, snapshot, [])",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.{FlowSnapshot}\n" <>
               "&FlowSnapshot.restore/3",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot, as: Snapshot\n" <>
               "&Snapshot.restore/2",
             restore_entry
           )

    assert entrypoint_used?(
             "flow |> Storyarn.Flows.Versioning.FlowSnapshot.restore(snapshot)",
             restore_entry
           )

    assert entrypoint_used?(
             "apply(Storyarn.Flows.Versioning.FlowSnapshot, :restore, [flow, snapshot, []])",
             restore_entry
           )

    assert entrypoint_used?(
             "Kernel.apply(Storyarn.Flows.Versioning.FlowSnapshot, :restore, args)",
             restore_entry
           )

    assert entrypoint_used?(
             "defdelegate restore(flow, snapshot, opts), " <>
               "to: Storyarn.Flows.Versioning.FlowSnapshot",
             restore_entry
           )

    assert entrypoint_used?(
             "import Storyarn.Flows.Versioning.FlowSnapshot, only: [restore: 3]",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(flow, snapshot) do\n" <>
               "  module = FlowSnapshot\n" <>
               "  module.restore(flow, snapshot, [])\n" <>
               "end",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "@snapshot_module FlowSnapshot\n" <>
               "def run(flow, snapshot), do: @snapshot_module.restore(flow, snapshot, [])",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(opts, flow, snapshot) do\n" <>
               "  Keyword.get(opts, :snapshot_module, FlowSnapshot).restore(flow, snapshot, [])\n" <>
               "end",
             restore_entry
           )

    assert entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(flow, snapshot) do\n" <>
               "  module = FlowSnapshot\n" <>
               "  apply(module, :restore, [flow, snapshot, []])\n" <>
               "end",
             restore_entry
           )

    assert entrypoint_used?(
             "defdelegate rebuild_project_variable_references(project_id), " <>
               "to: Storyarn.Sheets.References.Commands.VariableProjection, " <>
               "as: :rebuild_project",
             sheet_projection_entry
           )

    refute entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\nFlowSnapshot.build(flow)",
             restore_entry
           )

    refute entrypoint_used?(
             "Storyarn.Sheets.Versioning.SheetSnapshot.restore(sheet, snapshot, [])",
             restore_entry
           )

    refute entrypoint_used?(
             "Storyarn.Projects.References.update_flow_node_variable_references(node)",
             project_reference_entry
           )

    refute entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def choose_module do\n" <>
               "  module = FlowSnapshot\n" <>
               "  module\n" <>
               "end\n" <>
               "def run(module, flow, snapshot), do: module.restore(flow, snapshot, [])",
             restore_entry
           )
  end

  test "local call graph rejects undeclared public wrappers around function-scoped entrypoints" do
    source = ~S"""
    defmodule Storyarn.Flows.Versioning.FlowSnapshot do
      def restore(flow, snapshot, opts), do: {:ok, flow, snapshot, opts}
      def restore_snapshot(flow, snapshot, opts), do: restore(flow, snapshot, opts)

      def unsafe_restore(flow, snapshot, opts) do
        restore_through_private_helper(flow, snapshot, opts)
      end

      def build(flow), do: flow

      defp restore_through_private_helper(flow, snapshot, opts) do
        restore(flow, snapshot, opts)
      end
    end
    """

    entry = %{
      module: "Storyarn.Flows.Versioning.FlowSnapshot",
      path: "fixture_flow_snapshot.ex",
      functions: [restore: 3, restore_snapshot: 3]
    }

    sources = [parsed_source("fixture_flow_snapshot.ex", source)]

    assert unreviewed_public_wrappers([entry], sources) == [
             %{
               module: "Storyarn.Flows.Versioning.FlowSnapshot",
               path: "fixture_flow_snapshot.ex",
               function: {:unsafe_restore, 3}
             }
           ]
  end

  test "local call graph treats an omitted default arity as a public wrapper" do
    source = ~S"""
    defmodule Storyarn.Flows.Versioning.FlowSnapshot do
      def restore(flow, snapshot, opts \\ []), do: {:ok, flow, snapshot, opts}
    end
    """

    entry = %{
      module: "Storyarn.Flows.Versioning.FlowSnapshot",
      path: "fixture_default_restore.ex",
      functions: [restore: 3]
    }

    sources = [parsed_source("fixture_default_restore.ex", source)]

    assert unreviewed_public_wrappers([entry], sources) == [
             %{
               module: "Storyarn.Flows.Versioning.FlowSnapshot",
               path: "fixture_default_restore.ex",
               function: {:restore, 2}
             }
           ]
  end

  defp policy, do: DependencyPolicy.load!(@policy_path)

  defp entrypoint_callers(entry, sources) do
    sources
    |> Enum.reject(&(&1.path == entry.path))
    |> Enum.filter(&entrypoint_used_ast?(&1.ast, &1.aliases, entry))
    |> Enum.map(& &1.path)
    |> Enum.sort()
  end

  defp parsed_sources do
    Enum.map(source_paths(), &parsed_source(&1, File.read!(&1)))
  end

  defp parsed_source(path, source) do
    ast = quoted!(source)
    %{path: path, ast: ast, aliases: alias_bindings(ast)}
  end

  defp source_paths do
    @storyarn_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp entrypoint_used?(source, %{functions: :all} = entry) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)

    entrypoint_used_ast?(ast, aliases, entry)
  end

  defp entrypoint_used?(source, entry) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)

    entrypoint_used_ast?(ast, aliases, entry)
  end

  defp entrypoint_used_ast?(ast, aliases, %{functions: :all} = entry) do
    ast_references_module?(ast, entry.module, aliases)
  end

  defp entrypoint_used_ast?(ast, aliases, entry) do
    # Dynamic receivers can only be resolved statically when this source file
    # anchors them to the target module through a literal, alias, attribute or
    # expression. Runtime-only module values with no such anchor remain outside
    # this lib/**/*.ex source ratchet.
    ast_references_module?(ast, entry.module, aliases) and
      (imports_module?(ast, entry.module, aliases) or
         ast_calls_functions?(ast, entry.module, entry.functions, aliases))
  end

  defp ast_calls_functions?(ast, target, functions, aliases) do
    base_context = receiver_context(ast, target, aliases)

    restricted_call_in_ast?(ast, target, functions, base_context) or
      Enum.any?(function_scopes(ast), fn scope ->
        tainted = tainted_receiver_variables(scope.ast, target, base_context)
        context = %{base_context | tainted: tainted}
        restricted_call_in_ast?(scope.body, target, functions, context)
      end)
  end

  defp restricted_call_in_ast?(ast, target, functions, context) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        {node, found? or restricted_call?(node, target, functions, context)}
      end)

    found?
  end

  defp restricted_call?({:|>, _, [_left, right]}, target, functions, context) do
    remote_call_matches?(right, target, functions, context, 1)
  end

  defp restricted_call?({:&, _, [{:/, _, [{{:., _, [module_ast, function]}, _, []}, arity]}]}, target, functions, context)
       when is_atom(function) and is_integer(arity) do
    target_module?(module_ast, target, context) and
      function_matches?(functions, function, arity)
  end

  defp restricted_call?({:defdelegate, _, [head, opts]}, target, functions, context) when is_list(opts) do
    with {:ok, function, arity} <- delegated_function(head, opts),
         module_ast when not is_nil(module_ast) <- Keyword.get(opts, :to) do
      target_module?(module_ast, target, context) and
        function_matches?(functions, function, arity)
    else
      _other -> false
    end
  end

  defp restricted_call?({:apply, _, [module_ast, function, args]}, target, functions, context) do
    apply_matches?(module_ast, function, args, target, functions, context)
  end

  defp restricted_call?({{:., _, [kernel_ast, :apply]}, _, [module_ast, function, args]}, target, functions, context) do
    kernel_module?(kernel_ast, context) and
      apply_matches?(module_ast, function, args, target, functions, context)
  end

  defp restricted_call?(node, target, functions, context) do
    remote_call_matches?(node, target, functions, context, 0)
  end

  defp remote_call_matches?({{:., _, [module_ast, function]}, _, arguments}, target, functions, context, piped_arguments)
       when is_atom(function) and is_list(arguments) do
    target_module?(module_ast, target, context) and
      function_matches?(functions, function, length(arguments) + piped_arguments)
  end

  defp remote_call_matches?(_node, _target, _functions, _context, _piped_arguments), do: false

  defp apply_matches?(module_ast, function, args, target, functions, context) do
    target_module?(module_ast, target, context) and
      function_matches?(functions, literal_atom(function), literal_list_arity(args))
  end

  defp literal_atom(value) when is_atom(value), do: value
  defp literal_atom(_value), do: :dynamic

  defp literal_list_arity(arguments) when is_list(arguments), do: length(arguments)
  defp literal_list_arity(_arguments), do: :dynamic

  defp function_matches?(:all, _function, _arity), do: true
  defp function_matches?(_functions, :dynamic, _arity), do: true

  defp function_matches?(functions, function, :dynamic) do
    Enum.any?(functions, fn {allowed_function, _arity} -> allowed_function == function end)
  end

  defp function_matches?(functions, function, arity), do: {function, arity} in functions

  defp delegated_function({:when, _, [head | _guards]}, opts), do: delegated_function(head, opts)

  defp delegated_function({name, _, arguments}, opts) when is_atom(name) and is_list(arguments) do
    {:ok, Keyword.get(opts, :as, name), length(arguments)}
  end

  defp delegated_function(_head, _opts), do: :error

  defp imports_module?(ast, target, aliases) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:import, _, [module_ast | _opts]} = node, found? ->
          {node, found? or literal_target_module?(module_ast, target, aliases)}

        node, found? ->
          {node, found?}
      end)

    found?
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

        module, found? when is_atom(module) ->
          {module, found? or module_atom_name(module) == target}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp target_module?(module_ast, target, context) do
    direct_target_reference?(module_ast, target, context) or
      module_expression_references_target?(module_ast, target, context)
  end

  defp direct_target_reference?({:__aliases__, _, segments}, target, context) do
    target_parts = String.split(target, ".")
    target_parts in expanded_modules(segments, context.aliases)
  end

  defp direct_target_reference?({:__MODULE__, _, _arguments}, target, context), do: context.self_module == target

  defp direct_target_reference?({:@, _, [{name, _, _arguments}]}, _target, context) when is_atom(name),
    do: MapSet.member?(context.attributes, name)

  defp direct_target_reference?({name, _, variable_context}, _target, context)
       when is_atom(name) and (is_atom(variable_context) or is_nil(variable_context)),
       do: MapSet.member?(context.tainted, name)

  defp direct_target_reference?(module, target, _context) when is_atom(module), do: module_atom_name(module) == target

  defp direct_target_reference?(_module, _target, _context), do: false

  defp module_expression_references_target?(module_ast, target, context) do
    {_ast, found?} =
      Macro.prewalk(module_ast, false, fn node, found? ->
        {node, found? or direct_target_reference?(node, target, context)}
      end)

    found?
  end

  defp literal_target_module?({:__aliases__, _, segments}, target, aliases) do
    target_parts = String.split(target, ".")
    target_parts in expanded_modules(segments, aliases)
  end

  defp literal_target_module?(module, target, _aliases) when is_atom(module), do: module_atom_name(module) == target
  defp literal_target_module?(_module, _target, _aliases), do: false

  defp kernel_module?(module_ast, context), do: literal_target_module?(module_ast, "Kernel", context.aliases)

  defp receiver_context(ast, target, aliases, self_module \\ nil) do
    base = %{aliases: aliases, attributes: MapSet.new(), tainted: MapSet.new(), self_module: self_module}
    %{base | attributes: target_module_attributes(ast, target, base)}
  end

  defp target_module_attributes(ast, target, base_context) do
    Enum.reduce_while(1..6, MapSet.new(), fn _pass, attributes ->
      context = %{base_context | attributes: attributes}
      next_attributes = collect_target_module_attributes(ast, target, context, attributes)

      if MapSet.equal?(next_attributes, attributes),
        do: {:halt, next_attributes},
        else: {:cont, next_attributes}
    end)
  end

  defp collect_target_module_attributes(ast, target, context, attributes) do
    {_ast, collected} =
      Macro.prewalk(ast, attributes, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          if module_expression_references_target?(value, target, context),
            do: {node, MapSet.put(acc, name)},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    collected
  end

  defp tainted_receiver_variables(ast, target, base_context) do
    Enum.reduce_while(1..6, MapSet.new(), fn _pass, tainted ->
      context = %{base_context | tainted: tainted}
      next_tainted = collect_tainted_receiver_variables(ast, target, context, tainted)

      if MapSet.equal?(next_tainted, tainted),
        do: {:halt, next_tainted},
        else: {:cont, next_tainted}
    end)
  end

  defp collect_tainted_receiver_variables(ast, target, context, tainted) do
    {_ast, collected} =
      Macro.prewalk(ast, tainted, fn
        {operator, _, [left, right]} = node, acc when operator in [:=, :<-, :\\] ->
          if module_expression_references_target?(right, target, context),
            do: {node, MapSet.union(acc, bound_variable_names(left))},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    collected
  end

  defp bound_variable_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, variable_context} = node, names
        when is_atom(name) and name != :_ and (is_atom(variable_context) or is_nil(variable_context)) ->
          {node, MapSet.put(names, name)}

        node, names ->
          {node, names}
      end)

    names
  end

  defp function_scopes(ast) do
    {_ast, scopes} =
      Macro.prewalk(ast, [], fn
        {visibility, _, [head, options]} = node, scopes
        when visibility in [:def, :defp] and is_list(options) ->
          case Keyword.fetch(options, :do) do
            {:ok, body} ->
              scope = %{
                visibility: visibility,
                identities: defined_function_identities(head),
                body: body,
                ast: {:__block__, [], [head, body]}
              }

              {node, [scope | scopes]}

            :error ->
              {node, scopes}
          end

        {visibility, _, [head]} = node, scopes when visibility in [:def, :defp] ->
          scope = %{
            visibility: visibility,
            identities: defined_function_identities(head),
            body: nil,
            ast: head
          }

          {node, [scope | scopes]}

        node, scopes ->
          {node, scopes}
      end)

    Enum.reverse(scopes)
  end

  defp unreviewed_public_wrappers(entries, sources) do
    entries
    |> Enum.group_by(& &1.module)
    |> Enum.flat_map(&unreviewed_module_wrappers(&1, sources))
    |> Enum.sort_by(&{&1.module, &1.path, &1.function})
  end

  defp unreviewed_module_wrappers({module, module_entries}, sources) do
    if Enum.any?(module_entries, &(&1.functions == :all)) do
      []
    else
      source_path = module_entries |> hd() |> Map.fetch!(:path)
      declared = module_entries |> Enum.flat_map(& &1.functions) |> MapSet.new()
      source = Enum.find(sources, &(&1.path == source_path))
      unreviewed_source_wrappers(source, module, source_path, declared)
    end
  end

  defp unreviewed_source_wrappers(nil, _module, _source_path, _declared), do: []

  defp unreviewed_source_wrappers(source, module, source_path, declared) do
    source.ast
    |> public_wrappers_reaching_entrypoint(module, source.aliases, declared)
    |> Enum.map(&%{module: module, path: source_path, function: &1})
  end

  defp public_wrappers_reaching_entrypoint(ast, module, aliases, declared) do
    scopes = function_scopes(ast)
    known_functions = scopes |> Enum.flat_map(& &1.identities) |> MapSet.new()
    base_context = receiver_context(ast, module, aliases, module)

    graph =
      Enum.reduce(scopes, %{}, fn scope, graph ->
        add_scope_to_privileged_graph(
          scope,
          graph,
          known_functions,
          module,
          declared,
          base_context
        )
      end)

    reachable = privileged_reachable_functions(graph, declared)

    scopes
    |> Enum.filter(&(&1.visibility == :def))
    |> Enum.flat_map(& &1.identities)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(declared, &1))
    |> Enum.filter(&MapSet.member?(reachable, &1))
    |> Enum.sort()
  end

  defp add_scope_to_privileged_graph(scope, graph, known_functions, module, declared, base_context) do
    calls = scope.body |> local_function_calls() |> MapSet.intersection(known_functions)

    context = %{
      base_context
      | tainted: tainted_receiver_variables(scope.ast, module, base_context)
    }

    direct_remote_reach? =
      not is_nil(scope.body) and
        restricted_call_in_ast?(scope.body, module, MapSet.to_list(declared), context)

    Enum.reduce(scope.identities, graph, fn identity, acc ->
      add_identity_to_privileged_graph(acc, scope, identity, calls, direct_remote_reach?)
    end)
  end

  defp add_identity_to_privileged_graph(graph, scope, identity, calls, direct_remote_reach?) do
    edges = default_delegate_edge(scope, identity, calls)
    edges = if direct_remote_reach?, do: MapSet.put(edges, :privileged), else: edges
    Map.update(graph, identity, edges, &MapSet.union(&1, edges))
  end

  defp privileged_reachable_functions(graph, declared) do
    initial = MapSet.put(declared, :privileged)

    Enum.reduce_while(1..(map_size(graph) + 1), initial, fn _pass, reachable ->
      next = propagate_privileged_reachability(graph, reachable)

      if MapSet.equal?(next, reachable), do: {:halt, next}, else: {:cont, next}
    end)
  end

  defp propagate_privileged_reachability(graph, reachable) do
    Enum.reduce(graph, reachable, fn {caller, callees}, acc ->
      if MapSet.disjoint?(callees, reachable), do: acc, else: MapSet.put(acc, caller)
    end)
  end

  defp local_function_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [_left, {function, _, arguments}]} = node, calls
        when is_atom(function) and is_list(arguments) ->
          {node, MapSet.put(calls, {function, length(arguments) + 1})}

        {:&, _, [{:/, _, [{function, _, context}, arity]}]} = node, calls
        when is_atom(function) and (is_atom(context) or is_nil(context)) and is_integer(arity) ->
          {node, MapSet.put(calls, {function, arity})}

        {function, _, arguments} = node, calls when is_atom(function) and is_list(arguments) ->
          {node, MapSet.put(calls, {function, length(arguments)})}

        node, calls ->
          {node, calls}
      end)

    calls
  end

  defp default_delegate_edge(%{identities: identities}, identity, calls) do
    case List.last(identities) do
      nil -> calls
      ^identity -> calls
      maximum_arity_identity -> MapSet.put(calls, maximum_arity_identity)
    end
  end

  defp defined_function_identities({:when, _, [head | _guards]}), do: defined_function_identities(head)

  defp defined_function_identities({name, _, arguments}) when is_atom(name) and is_list(arguments) do
    maximum_arity = length(arguments)
    defaults = Enum.count(arguments, &match?({:\\, _, [_argument, _default]}, &1))

    for arity <- (maximum_arity - defaults)..maximum_arity, do: {name, arity}
  end

  defp defined_function_identities({name, _, nil}) when is_atom(name), do: [{name, 0}]
  defp defined_function_identities(_head), do: []

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

  defp valid_function_scope?(:all), do: true

  defp valid_function_scope?([_function | _rest] = functions) do
    Enum.all?(functions, fn
      {name, arity} when is_atom(name) and is_integer(arity) and arity >= 0 -> true
      _other -> false
    end) and functions == Enum.uniq(functions)
  end

  defp valid_function_scope?(_functions), do: false

  defp function_scope_label(:all), do: "(all functions)"
  defp function_scope_label(functions), do: inspect(functions)

  defp entry_identity(entry), do: {entry.module, entry.functions}

  defp disjoint_function_scopes?(entries) do
    entries
    |> Enum.group_by(& &1.module)
    |> Enum.all?(fn {_module, module_entries} ->
      scopes = Enum.map(module_entries, & &1.functions)

      case scopes do
        [:all] ->
          true

        functions ->
          flattened = List.flatten(functions)
          :all not in functions and flattened == Enum.uniq(flattened)
      end
    end)
  end

  defp module_atom_name(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp quoted!(source), do: Code.string_to_quoted!(source, columns: true)
  defp module_parts(segments), do: Enum.map(segments, &Atom.to_string/1)
end
