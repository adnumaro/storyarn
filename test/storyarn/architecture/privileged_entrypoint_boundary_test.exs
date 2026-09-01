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
    analyses = privileged_entrypoint_analyses(entries, sources)

    assert length(entries) == 72
    assert Enum.uniq_by(entries, &entry_identity/1) == entries
    assert disjoint_function_scopes?(entries)

    assert unreviewed_public_wrappers(entries, sources) == [], """
    A public function in a privileged target module reaches a reviewed
    function-scoped entrypoint without being declared as an entrypoint itself.

    Declare the wrapper explicitly with its exact callers, or keep the helper
    private so the reviewed entrypoint remains the only public route.
    """

    assert ambiguous_privileged_dispatches(analyses) == [], """
    A function-scoped privileged entrypoint is invoked through an opaque or
    ambiguously rebound module receiver. The ratchet cannot prove that receiver
    is the reviewed module.

    Replace the field dispatch, unsafe rebinding or shadowed variable with a
    direct call or an explicit callback anchored to the reviewed default module.
    """

    for {entry, source_analyses} <- analyses do
      assert File.regular?(entry.path), "privileged entrypoint path is missing: #{entry.path}"
      assert byte_size(entry.reason) > 0
      assert valid_function_scope?(entry.functions)
      refute Map.has_key?(entry, :anchored_dynamic_receiver)

      assert entry.allowed_callers == entry.allowed_callers |> Enum.uniq() |> Enum.sort()

      for caller <- entry.allowed_callers do
        assert File.regular?(caller), "privileged entrypoint caller is missing: #{caller}"
      end

      actual_callers = entrypoint_callers(entry, source_analyses)

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
             "Storyarn.Flows.Versioning.FlowSnapshot |> apply(:restore, [flow, snapshot, []])",
             restore_entry
           )

    assert entrypoint_used?(
             "Function.capture(Storyarn.Flows.Versioning.FlowSnapshot, :restore, 3)",
             restore_entry
           )

    stable_dynamic_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(opts, flow, snapshot) do\n" <>
        "  module = Keyword.get(opts, :snapshot_module, FlowSnapshot)\n" <>
        "  restore = &module.restore/3\n" <>
        "  restore.(flow, snapshot, [])\n" <>
        "end"

    assert entrypoint_used?(stable_dynamic_receiver, restore_entry)
    refute ambiguous_entrypoint_used?(stable_dynamic_receiver, restore_entry)

    field_derived_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(context, flow, snapshot) do\n" <>
        "  _anchor = FlowSnapshot\n" <>
        "  module = context.recovery\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(field_derived_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(field_derived_receiver, restore_entry)

    rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  module = Other\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(rebound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(rebound_receiver, restore_entry)

    stable_rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  module = FlowSnapshot\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    assert entrypoint_used?(stable_rebound_receiver, restore_entry)
    refute ambiguous_entrypoint_used?(stable_rebound_receiver, restore_entry)

    conditional_rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flag, flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  module = if(flag, do: Other, else: module)\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(conditional_rebound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(conditional_rebound_receiver, restore_entry)

    derived_rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  module = normalize(module)\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(derived_rebound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(derived_rebound_receiver, restore_entry)

    laundered_rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flag, flow, snapshot) do\n" <>
        "  candidate = if(flag, do: Other, else: FlowSnapshot)\n" <>
        "  module = FlowSnapshot\n" <>
        "  module = candidate\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(laundered_rebound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(laundered_rebound_receiver, restore_entry)

    conflicting_alias_rebound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot, as: Snapshot\n" <>
        "alias Storyarn.Other, as: Snapshot\n" <>
        "def run(flow, snapshot) do\n" <>
        "  module = Snapshot\n" <>
        "  module = Snapshot\n" <>
        "  module.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(conflicting_alias_rebound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(conflicting_alias_rebound_receiver, restore_entry)

    shadowed_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(modules, flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  Enum.each(modules, fn module -> module.restore(flow, snapshot, []) end)\n" <>
        "end"

    refute entrypoint_used?(shadowed_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(shadowed_receiver, restore_entry)

    stable_guarded_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flag, value, flow, snapshot) do\n" <>
        "  module = FlowSnapshot\n" <>
        "  cond do\n" <>
        "    flag and module == FlowSnapshot -> module.restore(flow, snapshot, [])\n" <>
        "    true ->\n" <>
        "      case value do\n" <>
        "        ^module -> module.restore(flow, snapshot, [])\n" <>
        "        _other -> :ok\n" <>
        "      end\n" <>
        "  end\n" <>
        "end"

    assert entrypoint_used?(stable_guarded_receiver, restore_entry)
    refute ambiguous_entrypoint_used?(stable_guarded_receiver, restore_entry)

    refute entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(context, flow, snapshot) do\n" <>
               "  _anchor = FlowSnapshot\n" <>
               "  context.unrelated.restore(flow, snapshot, [])\n" <>
               "end",
             restore_entry
           )

    assert ambiguous_entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(context, flow, snapshot) do\n" <>
               "  _anchor = FlowSnapshot\n" <>
               "  context.unrelated.restore(flow, snapshot, [])\n" <>
               "end",
             restore_entry
           )

    compound_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(flow, snapshot) do\n" <>
        "  context = %{snapshot_module: FlowSnapshot, recovery: Other}\n" <>
        "  context.recovery.restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(compound_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(compound_receiver, restore_entry)

    access_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(context, flow, snapshot) do\n" <>
        "  _anchor = FlowSnapshot\n" <>
        "  context[:recovery].restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(access_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(access_receiver, restore_entry)

    explicit_access_receiver =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(context, flow, snapshot) do\n" <>
        "  _anchor = FlowSnapshot\n" <>
        "  Access.get(context, :recovery).restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(explicit_access_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(explicit_access_receiver, restore_entry)

    aliased_access_receiver =
      "alias Access, as: A\n" <>
        "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(context, flow, snapshot) do\n" <>
        "  _anchor = FlowSnapshot\n" <>
        "  A.get(context, :recovery).restore(flow, snapshot, [])\n" <>
        "end"

    refute entrypoint_used?(aliased_access_receiver, restore_entry)
    assert ambiguous_entrypoint_used?(aliased_access_receiver, restore_entry)

    direct_and_opaque_receivers =
      "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
        "def run(context, flow, snapshot) do\n" <>
        "  FlowSnapshot.restore(flow, snapshot, [])\n" <>
        "  context.recovery.restore(flow, snapshot, [])\n" <>
        "end"

    assert entrypoint_used?(direct_and_opaque_receivers, restore_entry)
    assert ambiguous_entrypoint_used?(direct_and_opaque_receivers, restore_entry)

    assert ambiguous_entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(context, flow, snapshot) do\n" <>
               "  _anchor = FlowSnapshot\n" <>
               "  context.recovery.restore(flow, snapshot, [])\n" <>
               "end",
             restore_entry
           )

    refute ambiguous_entrypoint_used?(
             "alias Storyarn.Flows.Versioning.FlowSnapshot\n" <>
               "def run(context, flow), do: context.recovery.build(flow)",
             restore_entry
           )

    refute ambiguous_entrypoint_used?(
             "def run(context, flow, snapshot), " <>
               "do: context.recovery.restore(flow, snapshot, [])",
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

    refute entrypoint_used?(
             "import Storyarn.Flows.Versioning.FlowSnapshot, only: [build: 1]",
             restore_entry
           )

    refute entrypoint_used?(
             "import Storyarn.Flows.Versioning.FlowSnapshot, " <>
               "except: [restore: 2, restore: 3]",
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

  defp entrypoint_callers(entry, source_analyses) do
    source_analyses
    |> Enum.reject(&(&1.path == entry.path))
    |> Enum.filter(& &1.used?)
    |> Enum.map(& &1.path)
    |> Enum.sort()
  end

  defp privileged_entrypoint_analyses(entries, sources) do
    Enum.map(entries, fn entry ->
      source_analyses =
        Enum.map(sources, fn source ->
          source.ast
          |> entrypoint_analysis_ast(
            source.aliases,
            entry,
            MapSet.member?(source.module_references, entry.module)
          )
          |> Map.put(:path, source.path)
        end)

      {entry, source_analyses}
    end)
  end

  defp parsed_sources do
    Enum.map(source_paths(), &parsed_source(&1, File.read!(&1)))
  end

  defp parsed_source(path, source) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)

    %{
      path: path,
      ast: ast,
      aliases: aliases,
      module_references: referenced_modules(ast, aliases)
    }
  end

  defp source_paths do
    @storyarn_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp entrypoint_used?(source, entry) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)

    entrypoint_analysis_ast(ast, aliases, entry).used?
  end

  defp ambiguous_entrypoint_used?(source, entry) do
    ast = quoted!(source)
    aliases = alias_bindings(ast)

    entrypoint_analysis_ast(ast, aliases, entry).ambiguous?
  end

  defp entrypoint_analysis_ast(ast, aliases, entry) do
    entrypoint_analysis_ast(ast, aliases, entry, ast_references_module?(ast, entry.module, aliases))
  end

  defp entrypoint_analysis_ast(_ast, _aliases, _entry, false), do: empty_call_analysis()

  defp entrypoint_analysis_ast(_ast, _aliases, %{functions: :all}, true) do
    %{used?: true, ambiguous?: false}
  end

  defp entrypoint_analysis_ast(ast, aliases, entry, true) do
    # Dynamic receivers can only be resolved statically when this source file
    # anchors them to the target module through a literal, alias, attribute or
    # expression. Runtime-only module values with no such anchor remain outside
    # this lib/**/*.ex source ratchet.
    analysis = restricted_entrypoint_call_analysis(ast, entry, aliases)
    %{analysis | used?: imports_module?(ast, entry.module, entry.functions, aliases) or analysis.used?}
  end

  defp restricted_entrypoint_call_analysis(ast, entry, aliases) do
    base_context = receiver_context(ast, entry.module, aliases, nil)

    Enum.reduce(
      function_scopes(ast),
      restricted_call_analysis_in_ast(ast, entry.module, entry.functions, base_context),
      fn
        scope, analysis ->
          tainted = tainted_receiver_variables(scope.ast, entry.module, base_context)
          tainted_context = %{base_context | tainted: tainted}
          ambiguous = suspect_receiver_variables(scope, entry.module, tainted_context)

          context = %{tainted_context | ambiguous: ambiguous}

          merge_call_analysis(
            analysis,
            restricted_call_analysis_in_ast(scope.body, entry.module, entry.functions, context)
          )
      end
    )
  end

  defp restricted_call_in_ast?(ast, target, functions, context) do
    restricted_call_analysis_in_ast(ast, target, functions, context).used?
  end

  defp restricted_call_analysis_in_ast(ast, target, functions, context) do
    {_ast, analysis} =
      ast
      |> normalize_pipeline_calls()
      |> Macro.prewalk(empty_call_analysis(), fn node, analysis ->
        used? = restricted_call?(node, target, functions, context)
        ambiguous? = opaque_restricted_call?(node, functions, context)

        {node,
         %{
           used?: analysis.used? or used?,
           ambiguous?: analysis.ambiguous? or ambiguous?
         }}
      end)

    analysis
  end

  defp empty_call_analysis, do: %{used?: false, ambiguous?: false}

  defp merge_call_analysis(left, right) do
    %{used?: left.used? or right.used?, ambiguous?: left.ambiguous? or right.ambiguous?}
  end

  defp opaque_restricted_call?({:|>, _, [_left, right]}, functions, context) do
    opaque_remote_call_matches?(right, functions, context, 1)
  end

  defp opaque_restricted_call?({:&, _, [{:/, _, [{{:., _, [module_ast, function]}, _, []}, arity]}]}, functions, context)
       when is_atom(function) and is_integer(arity) do
    opaque_receiver?(module_ast, context) and function_matches?(functions, function, arity)
  end

  defp opaque_restricted_call?({:defdelegate, _, [head, opts]}, functions, context) when is_list(opts) do
    with {:ok, function, arity} <- delegated_function(head, opts),
         module_ast when not is_nil(module_ast) <- Keyword.get(opts, :to) do
      opaque_receiver?(module_ast, context) and function_matches?(functions, function, arity)
    else
      _other -> false
    end
  end

  defp opaque_restricted_call?({:apply, _, [module_ast, function, args]}, functions, context) do
    opaque_apply_matches?(module_ast, function, args, functions, context)
  end

  defp opaque_restricted_call?({{:., _, [kernel_ast, :apply]}, _, [module_ast, function, args]}, functions, context) do
    kernel_module?(kernel_ast, context) and
      opaque_apply_matches?(module_ast, function, args, functions, context)
  end

  defp opaque_restricted_call?({{:., _, [function_ast, :capture]}, _, [module_ast, function, arity]}, functions, context) do
    function_module?(function_ast, context) and
      opaque_receiver?(module_ast, context) and
      function_matches?(functions, literal_atom(function), literal_capture_arity(arity))
  end

  defp opaque_restricted_call?(node, functions, context) do
    opaque_remote_call_matches?(node, functions, context, 0)
  end

  defp opaque_remote_call_matches?({{:., _, [module_ast, function]}, _, arguments}, functions, context, piped_arguments)
       when is_atom(function) and is_list(arguments) do
    opaque_receiver?(module_ast, context) and
      function_matches?(functions, function, length(arguments) + piped_arguments)
  end

  defp opaque_remote_call_matches?(_node, _functions, _context, _piped_arguments), do: false

  defp opaque_apply_matches?(module_ast, function, args, functions, context) do
    opaque_receiver?(module_ast, context) and
      function_matches?(functions, literal_atom(function), literal_list_arity(args))
  end

  defp opaque_receiver?({name, _, variable_context}, context)
       when is_atom(name) and (is_atom(variable_context) or is_nil(variable_context)) do
    MapSet.member?(context.ambiguous, name)
  end

  defp opaque_receiver?(module_ast, context), do: opaque_field_receiver?(module_ast, context)

  defp opaque_field_receiver?({{:., metadata, [access, :get]}, _, [_container, _key]}, context) when is_list(metadata) do
    Keyword.get(metadata, :from_brackets, false) or
      literal_target_module?(access, "Access", context.aliases)
  end

  defp opaque_field_receiver?({{:., _, [_receiver, field]}, _, []}, _context) when is_atom(field), do: true
  defp opaque_field_receiver?(_module_ast, _context), do: false

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

  defp restricted_call?({{:., _, [function_ast, :capture]}, _, [module_ast, function, arity]}, target, functions, context) do
    function_module?(function_ast, context) and
      target_module?(module_ast, target, context) and
      function_matches?(functions, literal_atom(function), literal_capture_arity(arity))
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

  defp literal_capture_arity(arity) when is_integer(arity), do: arity
  defp literal_capture_arity(_arity), do: :dynamic

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

  defp imports_module?(ast, target, functions, aliases) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:import, _, [module_ast | import_args]} = node, found? ->
          imports_entrypoint? =
            literal_target_module?(module_ast, target, aliases) and
              import_includes_entrypoint?(import_args, functions)

          {node, found? or imports_entrypoint?}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp import_includes_entrypoint?([], _functions), do: true

  defp import_includes_entrypoint?([opts], functions) when is_list(opts) do
    case Keyword.fetch(opts, :only) do
      {:ok, only} when is_list(only) -> Enum.any?(functions, &(&1 in only))
      {:ok, _dynamic_only} -> true
      :error -> import_except_includes_entrypoint?(Keyword.get(opts, :except), functions)
    end
  end

  defp import_includes_entrypoint?(_dynamic_args, _functions), do: true

  defp import_except_includes_entrypoint?(except, functions) when is_list(except) do
    Enum.any?(functions, &(&1 not in except))
  end

  defp import_except_includes_entrypoint?(_except, _functions), do: true

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

  defp referenced_modules(ast, aliases) do
    initial =
      aliases
      |> Map.values()
      |> Enum.flat_map(& &1)
      |> MapSet.new(&Enum.join(&1, "."))

    {_ast, modules} =
      Macro.prewalk(ast, initial, fn
        {:__aliases__, _, segments} = node, modules ->
          expanded =
            segments
            |> expanded_modules(aliases)
            |> MapSet.new(&Enum.join(&1, "."))

          {node, MapSet.union(modules, expanded)}

        module, modules when is_atom(module) ->
          {module, MapSet.put(modules, module_atom_name(module))}

        node, modules ->
          {node, modules}
      end)

    modules
  end

  defp target_module?(module_ast, target, context) do
    not opaque_field_receiver?(module_ast, context) and
      (direct_target_reference?(module_ast, target, context) or
         module_expression_references_target?(module_ast, target, context))
  end

  defp direct_target_reference?({:__aliases__, _, segments}, target, context) do
    target_parts = String.split(target, ".")
    target_parts in expanded_modules(segments, context.aliases)
  end

  defp direct_target_reference?({:__MODULE__, _, _arguments}, target, context), do: context.self_module == target

  defp direct_target_reference?({:@, _, [{name, _, _arguments}]}, _target, context) when is_atom(name),
    do: MapSet.member?(context.attributes, name)

  defp direct_target_reference?({name, _, variable_context}, _target, context)
       when is_atom(name) and (is_atom(variable_context) or is_nil(variable_context)) do
    MapSet.member?(context.tainted, name) and not MapSet.member?(context.ambiguous, name)
  end

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

  defp provable_rebinding_target?({:__aliases__, _, segments}, target, context) do
    parts = module_parts(segments)
    target_parts = String.split(target, ".")

    parts == target_parts or
      case parts do
        [first | rest] ->
          context.aliases
          |> Map.get(first, [])
          |> Enum.map(&(&1 ++ rest))
          |> Enum.uniq()
          |> Kernel.==([target_parts])

        [] ->
          false
      end
  end

  defp provable_rebinding_target?({:__MODULE__, _, _arguments}, target, context), do: context.self_module == target

  defp provable_rebinding_target?(module, target, _context) when is_atom(module), do: module_atom_name(module) == target

  defp provable_rebinding_target?(_module, _target, _context), do: false

  defp kernel_module?(module_ast, context), do: literal_target_module?(module_ast, "Kernel", context.aliases)

  defp function_module?(module_ast, context), do: literal_target_module?(module_ast, "Function", context.aliases)

  defp normalize_pipeline_calls(ast) do
    Macro.postwalk(ast, fn
      {:|>, pipe_meta, [left, {{:., dot_meta, receiver}, call_meta, arguments}]}
      when is_list(arguments) ->
        {{:., dot_meta, receiver}, Keyword.merge(pipe_meta, call_meta), [left | arguments]}

      {:|>, pipe_meta, [left, {function, call_meta, arguments}]}
      when is_atom(function) and is_list(arguments) ->
        {function, Keyword.merge(pipe_meta, call_meta), [left | arguments]}

      node ->
        node
    end)
  end

  defp receiver_context(ast, target, aliases, self_module) do
    base = %{
      aliases: aliases,
      ambiguous: MapSet.new(),
      attributes: MapSet.new(),
      tainted: MapSet.new(),
      self_module: self_module
    }

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

  defp suspect_receiver_variables(scope, target, context) do
    unanchored_bindings = unanchored_receiver_bindings(scope, target, context)

    unsafe_rebindings =
      scope
      |> receiver_binding_counts()
      |> Enum.reduce(MapSet.new(), fn
        {name, count}, names when count > 1 ->
          if MapSet.member?(unanchored_bindings, name),
            do: MapSet.put(names, name),
            else: names

        {_name, _count}, names ->
          names
      end)

    Enum.reduce_while(1..6, unsafe_rebindings, fn _pass, suspects ->
      next_suspects = collect_field_derived_receiver_variables(scope.body, suspects, context)

      if MapSet.equal?(next_suspects, suspects),
        do: {:halt, next_suspects},
        else: {:cont, next_suspects}
    end)
  end

  defp unanchored_receiver_bindings(scope, target, context) do
    initial = function_head_bound_names(scope.head)

    {_ast, names} =
      Macro.prewalk(scope.body, initial, fn
        {operator, _, [left, right]} = node, acc when operator in [:=, :<-] ->
          if provable_rebinding_target?(right, target, context),
            do: {node, acc},
            else: {node, MapSet.union(acc, bound_pattern_names(left))}

        {:fn, _, clauses} = node, acc when is_list(clauses) ->
          {node, MapSet.union(acc, arrow_clause_bound_names(clauses))}

        {:case, _, [_value, options]} = node, acc when is_list(options) ->
          {node, MapSet.union(acc, arrow_clause_bound_names(Keyword.get(options, :do, [])))}

        {:receive, _, [options]} = node, acc when is_list(options) ->
          {node, MapSet.union(acc, arrow_clause_bound_names(Keyword.get(options, :do, [])))}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp receiver_binding_counts(scope) do
    scope.head
    |> function_head_bound_names()
    |> increment_binding_counts(%{})
    |> then(fn counts ->
      {_ast, counts} =
        Macro.prewalk(scope.body, counts, fn
          {operator, _, [left, _right]} = node, acc when operator in [:=, :<-] ->
            {node, increment_binding_counts(bound_pattern_names(left), acc)}

          {:fn, _, clauses} = node, acc when is_list(clauses) ->
            {node, increment_binding_counts(arrow_clause_bound_names(clauses), acc)}

          {:case, _, [_value, options]} = node, acc when is_list(options) ->
            {node, increment_binding_counts(arrow_clause_bound_names(Keyword.get(options, :do, [])), acc)}

          {:receive, _, [options]} = node, acc when is_list(options) ->
            {node, increment_binding_counts(arrow_clause_bound_names(Keyword.get(options, :do, [])), acc)}

          node, acc ->
            {node, acc}
        end)

      counts
    end)
  end

  defp function_head_bound_names({:when, _, [head | _guards]}), do: function_head_bound_names(head)

  defp function_head_bound_names({_name, _, arguments}) when is_list(arguments) do
    arguments
    |> Enum.flat_map(&bound_pattern_names/1)
    |> MapSet.new()
  end

  defp function_head_bound_names(_head), do: MapSet.new()

  defp bound_pattern_names({:\\, _, [pattern, _default]}), do: bound_pattern_names(pattern)

  defp bound_pattern_names(pattern) do
    {_ast, names} =
      Macro.prewalk(pattern, MapSet.new(), fn
        {:^, _, [_pinned]}, names ->
          {nil, names}

        {:when, _, [guarded_pattern | _guards]} = _node, names ->
          {guarded_pattern, names}

        {name, _, variable_context} = node, names
        when is_atom(name) and name != :_ and (is_atom(variable_context) or is_nil(variable_context)) ->
          {node, MapSet.put(names, name)}

        node, names ->
          {node, names}
      end)

    names
  end

  defp arrow_clause_bound_names(clauses) when is_list(clauses) do
    clauses
    |> Enum.flat_map(fn
      {:->, _, [patterns, _body]} when is_list(patterns) -> Enum.flat_map(patterns, &bound_pattern_names/1)
      _other -> []
    end)
    |> MapSet.new()
  end

  defp arrow_clause_bound_names(_clauses), do: MapSet.new()

  defp increment_binding_counts(names, counts) do
    Enum.reduce(names, counts, &Map.update(&2, &1, 1, fn count -> count + 1 end))
  end

  defp collect_field_derived_receiver_variables(ast, suspects, context) do
    {_ast, collected} =
      Macro.prewalk(ast, suspects, fn
        {operator, _, [left, right]} = node, acc when operator in [:=, :<-] ->
          if expression_references_opaque_receiver?(right, acc, context),
            do: {node, MapSet.union(acc, bound_pattern_names(left))},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    collected
  end

  defp expression_references_opaque_receiver?(ast, suspects, context) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {name, _, variable_context} = node, found?
        when is_atom(name) and (is_atom(variable_context) or is_nil(variable_context)) ->
          {node, found? or MapSet.member?(suspects, name)}

        node, found? ->
          {node, found? or opaque_field_receiver?(node, context)}
      end)

    found?
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
                head: head,
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
            head: head,
            body: nil,
            ast: head
          }

          {node, [scope | scopes]}

        node, scopes ->
          {node, scopes}
      end)

    Enum.reverse(scopes)
  end

  defp ambiguous_privileged_dispatches(analyses) do
    analyses
    |> Enum.reject(fn {entry, _source_analyses} -> entry.functions == :all end)
    |> Enum.flat_map(fn {entry, source_analyses} ->
      source_analyses
      |> Enum.filter(& &1.ambiguous?)
      |> Enum.map(&{entry.module, entry.functions, &1.path})
    end)
    |> Enum.uniq()
    |> Enum.sort()
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
