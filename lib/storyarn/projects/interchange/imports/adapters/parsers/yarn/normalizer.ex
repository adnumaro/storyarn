defmodule Storyarn.Projects.Imports.Parsers.Yarn.Normalizer do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportIssue
  alias Storyarn.Projects.Imports.Parsers.Yarn.Expression
  alias Storyarn.Projects.Imports.Parsers.Yarn.Layout
  alias Storyarn.Projects.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Projects.Imports.Parsers.Yarn.Shortcut
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerClassifier
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerSheets
  alias Storyarn.Projects.NameNormalizer

  @max_title_length 200
  @max_description_length 2_000
  # `blocks.variable_name` is backed by PostgreSQL varchar(255). Reject the
  # normalized identifier here so every declaration/use form fails during
  # parsing instead of letting a background materialization hit the database
  # limit after the user accepted the preview.
  @max_variable_name_length 255

  @spec normalize([map()]) :: {:ok, map(), [ImportIssue.t()], map()} | {:error, atom()}
  def normalize(documents) when is_list(documents) do
    with :ok <- validate_titles(documents),
         :ok <- validate_descriptions(documents),
         :ok <- validate_interpolations(documents) do
      # Declarations are collected before pruning: in the Yarn compiler they
      # are compile-time and flow-insensitive, so a `<<declare>>` after a
      # `<<jump>>`/`<<stop>>` still takes effect — the documented "Setup node"
      # pattern. Pruning first undeclared every variable the live graph read
      # from such a node and failed the whole import.
      {declarations, declaration_issues} = collect_declarations(documents)
      variable_name_issues = collect_variable_name_issues(documents)
      {documents, unreachable_issues} = prune_unreachable(documents)
      references = collect_references(documents)
      condition_references = collect_condition_references(documents)
      assignment_targets = collect_assignment_targets(documents)

      {variables, variable_issues} =
        merge_variables(declarations, references, condition_references, assignment_targets)

      speaker_classification = SpeakerClassifier.classify(documents)

      {sheets, speaker_sheet_ids} =
        build_sheets(variables, speaker_classification.sheet_speakers)

      flow_refs = Map.new(documents, &{&1.title, stable_id("flow", &1.title)})
      flow_shortcuts = build_flow_shortcuts(documents)

      {flows, flow_issues} =
        documents
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {document, index}, issues ->
          {flow, issues_for_flow} =
            build_flow(
              document,
              index,
              flow_refs,
              Map.fetch!(flow_shortcuts, document.title),
              speaker_sheet_ids
            )

          {flow, issues ++ issues_for_flow}
        end)

      issues =
        declaration_issues ++
          variable_name_issues ++
          unreachable_issues ++ variable_issues ++ speaker_classification.issues ++ flow_issues

      data = %{
        "storyarn_version" => "1.0.0",
        "export_version" => "1.0.0",
        "project" => %{
          "name" => "Yarn Spinner Import",
          "settings" => %{"import_source" => "yarn_spinner"}
        },
        "import_review" =>
          speaker_classification.review
          |> ReviewDecisions.put_allowed_actions()
          |> Map.put("variable_count", length(variables)),
        "sheets" => sheets,
        "flows" => flows,
        "scenes" => []
      }

      metadata = %{
        flow_count: length(flows),
        sheet_count: length(sheets),
        speaker_sheet_count: length(speaker_classification.sheet_speakers),
        presentation_channel_count: MapSet.size(speaker_classification.presentation_channels),
        possible_speaker_alias_count: speaker_classification.possible_alias_count,
        variable_count: length(variables),
        warning_count: Enum.count(issues, &(&1.severity == :warning)),
        error_count: Enum.count(issues, &(&1.severity == :error))
      }

      {:ok, data, issues, metadata}
    end
  end

  # Yarn authors keep writing after a `<<jump>>` or `<<stop>>`. The compiler
  # correctly drops that text — nothing can reach it — but the speaker review is
  # built by walking the AST, so it used to count speakers that never became
  # nodes. `ReviewDecisions.validate_plan_occurrences/2` then saw the two halves
  # disagree and failed the whole import with `:invalid_import_review`: a message
  # about the review, for a file whose only sin was dead code. Pruning here makes
  # both halves read the same story and reports the dead code as what it is.
  defp prune_unreachable(documents) do
    Enum.map_reduce(documents, [], fn document, issues ->
      {body, dropped} = prune_sequence(document.body, [], [])
      {%{document | body: body}, issues ++ Enum.map(dropped, &new_issue(:warning, :unreachable_yarn_code, &1))}
    end)
  end

  defp prune_sequence([], kept, dropped), do: {Enum.reverse(kept), dropped}

  defp prune_sequence([item | rest], kept, dropped) do
    {item, dropped} = prune_nested(item, dropped)

    if terminal_item?(item) do
      {Enum.reverse([item | kept]), dropped ++ Enum.map(rest, &item_meta/1)}
    else
      prune_sequence(rest, [item | kept], dropped)
    end
  end

  defp prune_nested({:options, options, meta}, dropped) do
    {options, dropped} =
      Enum.map_reduce(options, dropped, fn option, acc ->
        {body, acc} = prune_sequence(option.body, [], acc)
        {%{option | body: body}, acc}
      end)

    {{:options, options, meta}, dropped}
  end

  defp prune_nested({:if, branches, else_body, meta}, dropped) do
    {branches, dropped} =
      Enum.map_reduce(branches, dropped, fn branch, acc ->
        {body, acc} = prune_sequence(branch.body, [], acc)
        {%{branch | body: body}, acc}
      end)

    {else_body, dropped} = prune_sequence(else_body, [], dropped)
    {{:if, branches, else_body, meta}, dropped}
  end

  defp prune_nested(item, dropped), do: {item, dropped}

  # Only these end a sequence outright. An unresolvable jump is already a hard
  # error, so treating every jump as terminal costs nothing and keeps the rule
  # simple. `<<stop now>>` / `<<return 5>>` are NOT the zero-argument control
  # commands: the compiler reports them and continues, so pruning after them
  # would hide reachable content behind an already-reported problem.
  defp terminal_item?({:command, "jump", _args, _meta}), do: true

  defp terminal_item?({:command, name, args, _meta}) when name in ["stop", "return"] do
    args == nil or (is_binary(args) and String.trim(args) == "")
  end

  # Terminality propagates through control flow: an `<<if>>` whose every branch
  # ends terminally — with an `<<else>>` doing the same, otherwise the false
  # path falls through — cannot continue, and neither can an options block
  # whose every option body ends terminally. Without this, dialogue after such
  # a block was counted by the speaker review but never wired into the graph,
  # and the halves disagreeing failed the import as an unresolvable review.
  defp terminal_item?({:if, branches, else_body, _meta}) do
    branches != [] and terminal_body?(else_body) and Enum.all?(branches, &terminal_body?(&1.body))
  end

  defp terminal_item?({:options, options, _meta}) do
    options != [] and Enum.all?(options, &terminal_body?(&1.body))
  end

  defp terminal_item?(_item), do: false

  defp terminal_body?(items) when is_list(items) and items != [], do: terminal_item?(List.last(items))
  defp terminal_body?(_empty_or_missing), do: false

  defp item_meta({:line, _text, meta}), do: meta
  defp item_meta({:options, _options, meta}), do: meta
  defp item_meta({:if, _branches, _else_body, meta}), do: meta
  defp item_meta({:command, _name, _args, meta}), do: meta

  # Flow-insensitive like the compiler's own checks: an interpolation that
  # normalizes to nothing — `{$_}` — must fail the parse instead of being
  # silently rewritten to the shared fallback variable.
  defp validate_interpolations(documents) do
    invalid? =
      documents
      |> Enum.flat_map(&walk_items(&1.body))
      |> Enum.any?(fn
        {:line, text, _meta} ->
          Expression.invalid_interpolation?(text)

        {:options, options, _meta} ->
          Enum.any?(options, &Expression.invalid_interpolation?(&1.text))

        _item ->
          false
      end)

    if invalid?, do: {:error, :invalid_yarn_interpolation}, else: :ok
  end

  defp validate_titles(documents) do
    titles = Enum.map(documents, & &1.title)

    cond do
      Enum.any?(titles, &(String.length(&1) > @max_title_length)) ->
        {:error, :yarn_node_title_too_long}

      titles |> Enum.frequencies() |> Enum.any?(fn {_title, count} -> count > 1 end) ->
        {:error, :duplicate_yarn_node_title}

      true ->
        :ok
    end
  end

  defp validate_descriptions(documents) do
    if Enum.any?(documents, &description_too_long?/1),
      do: {:error, :yarn_node_description_too_long},
      else: :ok
  end

  defp description_too_long?(document) do
    case Map.get(document.headers, "description") do
      description when is_binary(description) ->
        String.length(description) > @max_description_length

      _no_description ->
        false
    end
  end

  defp collect_declarations(documents) do
    {declarations, issues} =
      documents
      |> Enum.flat_map(&walk_items(&1.body))
      |> Enum.reduce({%{}, []}, fn
        {:command, "declare", args, meta}, {declarations, issues} ->
          case Expression.declaration(args) do
            {:ok, declaration} ->
              register_declaration(declarations, Map.put(declaration, :meta, meta), meta, issues)

            {:error, _reason} ->
              {declarations, [new_issue(:error, :unsupported_yarn_declaration, meta) | issues]}
          end

        _item, acc ->
          acc
      end)

    {declarations, Enum.reverse(issues)}
  end

  # The namespace-wide collision pass below validates source spellings. This
  # collector only needs a deterministic declaration to build the block when a
  # collision has already made the plan non-executable.
  defp register_declaration(declarations, declaration, _meta, issues) do
    {Map.put_new(declarations, declaration.variable, declaration), issues}
  end

  # Validate the complete namespace across declarations and every semantic use.
  # Looking only at declarations misses both storage-boundary violations and
  # `$hasClueA` versus `$has_clue_a` collisions when one spelling appears only
  # in a condition, assignment, or interpolation. Issues intentionally contain
  # only stable codes and source locations, never the variable names themselves.
  defp collect_variable_name_issues(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(&variable_occurrences_for_item/1)
    |> Enum.group_by(& &1.variable)
    |> Enum.sort_by(fn {normalized, _occurrences} -> normalized end)
    |> Enum.flat_map(fn {normalized, occurrences} ->
      variable_length_issues(normalized, occurrences) ++ variable_collision_issues(occurrences)
    end)
  end

  defp variable_length_issues(normalized, [first | _rest]) do
    if String.length(normalized) > @max_variable_name_length,
      do: [new_issue(:error, :yarn_variable_name_too_long, first.meta)],
      else: []
  end

  defp variable_length_issues(_normalized, _occurrences), do: []

  defp variable_collision_issues(occurrences) do
    case Enum.uniq_by(occurrences, & &1.source_name) do
      [_single_spelling] ->
        []

      [_first_spelling, collision | _rest] ->
        [new_issue(:error, :yarn_variable_name_collision, collision.meta)]

      [] ->
        []
    end
  end

  defp variable_occurrences_for_item({:command, "declare", args, meta}) do
    case Expression.declaration(args) do
      {:ok, declaration} -> [Map.put(declaration, :meta, meta)]
      {:error, _reason} -> []
    end
  end

  defp variable_occurrences_for_item({:command, "set", args, meta}) do
    with_occurrence_meta(Expression.referenced_variable_occurrences(args), meta)
  end

  defp variable_occurrences_for_item({:line, text, meta}) do
    with_occurrence_meta(Expression.interpolated_variable_occurrences(text), meta)
  end

  defp variable_occurrences_for_item({:if, branches, _else_body, _meta}) do
    Enum.flat_map(branches, fn branch ->
      with_occurrence_meta(Expression.referenced_variable_occurrences(branch.condition), Map.get(branch, :meta, branch))
    end)
  end

  defp variable_occurrences_for_item({:options, options, _meta}) do
    Enum.flat_map(options, fn option ->
      interpolations = Expression.interpolated_variable_occurrences(option.text)

      conditions =
        case extract_option_condition(option.text) do
          {:ok, _label, nil} -> []
          {:ok, _label, condition} -> Expression.referenced_variable_occurrences(condition)
          {:error, :unsupported_yarn_condition} -> Expression.referenced_variable_occurrences(option.text)
        end

      with_occurrence_meta(interpolations ++ conditions, option)
    end)
  end

  defp variable_occurrences_for_item(_item), do: []

  defp with_occurrence_meta(occurrences, meta), do: Enum.map(occurrences, &Map.put(&1, :meta, meta))

  defp collect_references(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(fn
      {:line, text, _meta} ->
        Expression.interpolated_variables(text)

      {:command, "set", args, _meta} ->
        Expression.referenced_variables(args)

      {:command, _name, _args, _meta} ->
        []

      {:if, branches, _else_body, _meta} ->
        Enum.flat_map(branches, &Expression.referenced_variables(&1.condition))

      {:options, options, _meta} ->
        Enum.flat_map(options, fn option ->
          Expression.interpolated_variables(option.text) ++
            option_condition_references(option)
        end)
    end)
    |> MapSet.new()
  end

  defp collect_condition_references(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(fn
      {:if, branches, _else_body, _meta} ->
        Enum.flat_map(branches, &Expression.referenced_variables(&1.condition))

      {:options, options, _meta} ->
        Enum.flat_map(options, &option_condition_references/1)

      _item ->
        []
    end)
    |> MapSet.new()
  end

  defp collect_assignment_targets(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(fn
      {:command, "set", args, _meta} ->
        case Expression.referenced_variables(args) do
          [target | _references] -> [target]
          [] -> []
        end

      _item ->
        []
    end)
    |> MapSet.new()
  end

  defp option_condition_references(option) do
    case extract_option_condition(option.text) do
      {:ok, _label, nil} -> []
      {:ok, _label, condition} -> Expression.referenced_variables(condition)
      {:error, :unsupported_yarn_condition} -> Expression.referenced_variables(option.text)
    end
  end

  defp merge_variables(declarations, references, condition_references, assignment_targets) do
    undeclared = MapSet.difference(references, declarations |> Map.keys() |> MapSet.new())

    variables =
      undeclared
      |> Enum.reduce(declarations, fn variable, acc ->
        Map.put(acc, variable, %{variable: variable, value: "", type: "text", meta: nil})
      end)
      |> Map.values()
      |> Enum.sort_by(& &1.variable)

    issues =
      Enum.map(undeclared, fn variable ->
        cond do
          MapSet.member?(condition_references, variable) ->
            ImportIssue.new(:error, :undeclared_yarn_condition_variable)

          MapSet.member?(assignment_targets, variable) ->
            ImportIssue.new(:error, :undeclared_yarn_assignment_variable)

          true ->
            ImportIssue.new(:warning, :undeclared_yarn_variable)
        end
      end)

    {variables, issues}
  end

  defp build_sheets(variables, speakers) do
    variable_sheet = if variables == [], do: [], else: [build_variable_sheet(variables)]
    SpeakerSheets.append(variable_sheet, speakers)
  end

  defp build_variable_sheet(variables) do
    blocks =
      variables
      |> Enum.with_index()
      |> Enum.map(fn {variable, index} ->
        %{
          "id" => stable_id("variable_block", variable.variable),
          "type" => variable.type,
          "position" => index,
          "config" => %{"label" => Map.get(variable, :source_name) || variable.variable},
          "value" => %{"content" => variable.value},
          "is_constant" => false,
          "variable_name" => variable.variable,
          "scope" => "self"
        }
      end)

    %{
      "id" => stable_id("sheet", "yarn_variables"),
      "name" => "Yarn Variables",
      "shortcut" => "yarn",
      "description" => "Variables imported from Yarn Spinner declarations and references",
      "color" => "#06b6d4",
      "position" => 0,
      "blocks" => blocks
    }
  end

  defp build_flow_shortcuts(documents) do
    {shortcuts, _used} =
      documents
      |> Enum.with_index()
      |> Enum.reduce({%{}, MapSet.new()}, fn {document, index}, {shortcuts, used} ->
        base = NameNormalizer.shortcutify(document.title)
        fallback = "yarn-flow-#{index + 1}"
        shortcut = Shortcut.unique(base, used, fallback)
        {Map.put(shortcuts, document.title, shortcut), MapSet.put(used, shortcut)}
      end)

    shortcuts
  end

  defp build_flow(document, position, flow_refs, shortcut, speaker_sheet_ids) do
    flow_id = Map.fetch!(flow_refs, document.title)
    entry_id = stable_id("node", "#{flow_id}:entry")

    state = %{
      flow_id: flow_id,
      source: document.source,
      nodes: [node(entry_id, "entry", %{"label" => "Start"})],
      connections: [],
      next_index: 1,
      issues: [],
      flow_refs: flow_refs,
      speaker_sheet_ids: speaker_sheet_ids,
      annotation_anchors: %{},
      current_speaker: nil
    }

    {outgoing, state} = compile_items(document.body, [{entry_id, "output"}], state)

    state =
      if outgoing == [] do
        state
      else
        {exit_id, state} = add_node(state, "exit", %{"label" => "End", "exit_mode" => "terminal"})
        connect_many(state, outgoing, exit_id)
      end

    # Creation order, which `Layout` relies on to rank in a single pass.
    nodes = Enum.reverse(state.nodes)
    connections = Enum.reverse(state.connections)

    flow = %{
      "id" => flow_id,
      "name" => document.headers["title"] || document.title,
      "shortcut" => shortcut,
      "description" => document.headers["description"],
      "position" => position,
      "is_main" => position == 0,
      "settings" => %{"import_source" => "yarn_spinner"},
      "import_yarn_annotation_anchors" => state.annotation_anchors,
      "nodes" => Layout.assign_positions(nodes, connections, state.annotation_anchors),
      "connections" => connections
    }

    {flow, Enum.reverse(state.issues)}
  end

  defp compile_items([], incoming, state), do: {incoming, state}
  defp compile_items(_items, [], state), do: {[], state}

  defp compile_items([{:line, text, meta}, {:options, options, option_meta} | rest], incoming, state) do
    {outgoing, state} = compile_dialogue_with_options(text, meta, options, option_meta, incoming, state)
    compile_items(rest, outgoing, state)
  end

  defp compile_items([{:line, text, meta} | rest], incoming, state) do
    {speaker, dialogue} = SpeakerClassifier.split(text)

    data = dialogue_data(dialogue, speaker, text, meta, state, [])
    {node_id, state} = add_node(state, "dialogue", data)
    state = state |> track_speaker(speaker, dialogue) |> connect_many(incoming, node_id)
    compile_items(rest, [{node_id, "output"}], state)
  end

  defp compile_items([{:options, options, meta} | rest], incoming, state) do
    {outgoing, state} = compile_dialogue_with_options("", meta, options, meta, incoming, state)
    compile_items(rest, outgoing, state)
  end

  defp compile_items([{:if, branches, else_body, meta} | rest], incoming, state) do
    {outgoing, state} = compile_conditional(branches, else_body, meta, incoming, state)
    compile_items(rest, outgoing, state)
  end

  defp compile_items([{:command, "declare", _args, _meta} | rest], incoming, state) do
    compile_items(rest, incoming, state)
  end

  defp compile_items([{:command, "set", args, meta} | rest], incoming, state) do
    case Expression.assignment(args) do
      {:ok, assignment} ->
        {node_id, state} = add_node(state, "instruction", %{"assignments" => [assignment], "description" => ""})
        state = connect_many(state, incoming, node_id)
        compile_items(rest, [{node_id, "output"}], state)

      {:error, _reason} ->
        state = add_issue(state, :unsupported_yarn_assignment, meta, :error)
        {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command("set", args))
        compile_items(rest, outgoing, state)
    end
  end

  defp compile_items([{:command, "jump", target, meta} | rest], incoming, state) do
    case resolve_flow_ref(state.flow_refs, target) do
      nil ->
        state = add_issue(state, :unknown_yarn_jump_target, meta, :error)
        {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command("jump", target))
        compile_items(rest, outgoing, state)

      target_id ->
        data = %{"label" => "Jump", "exit_mode" => "flow_reference", "referenced_flow_id" => target_id}
        {node_id, state} = add_node(state, "exit", data)
        state = connect_many(state, incoming, node_id)
        compile_items(rest, [], state)
    end
  end

  defp compile_items([{:command, "detour", target, meta} | rest], incoming, state) do
    case resolve_flow_ref(state.flow_refs, target) do
      nil ->
        state = add_issue(state, :unknown_yarn_detour_target, meta, :error)
        {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command("detour", target))
        compile_items(rest, outgoing, state)

      target_id ->
        {node_id, state} = add_node(state, "subflow", %{"referenced_flow_id" => target_id})
        state = connect_many(state, incoming, node_id)
        compile_items(rest, [{node_id, "output"}], state)
    end
  end

  defp compile_items([{:command, "return", "", _meta} | rest], incoming, state) do
    {node_id, state} = add_node(state, "exit", %{"label" => "Return", "exit_mode" => "caller_return"})
    state = connect_many(state, incoming, node_id)
    compile_items(rest, [], state)
  end

  defp compile_items([{:command, "stop", "", _meta} | rest], incoming, state) do
    {node_id, state} = add_node(state, "exit", %{"label" => "Stop", "exit_mode" => "terminal"})
    state = connect_many(state, incoming, node_id)
    compile_items(rest, [], state)
  end

  defp compile_items([{:command, name, args, meta} | rest], incoming, state) when name in ["return", "stop"] do
    state = add_issue(state, :unsupported_yarn_control_command, meta, :error)
    {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command(name, args))
    compile_items(rest, outgoing, state)
  end

  defp compile_items([{:command, name, args, meta} | rest], incoming, state) when name in ["once", "endonce"] do
    state = add_issue(state, :unsupported_yarn_control_command, meta, :error)
    {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command(name, args))
    compile_items(rest, outgoing, state)
  end

  defp compile_items([{:command, name, args, meta} | rest], incoming, state) do
    state = add_issue(state, :unsupported_yarn_command, meta)
    {outgoing, state} = add_unsupported_annotation(state, incoming, meta, yarn_command(name, args))
    compile_items(rest, outgoing, state)
  end

  defp compile_dialogue_with_options(text, meta, options, _option_meta, incoming, state) do
    {speaker, dialogue} = SpeakerClassifier.split(text)
    {responses, state} = build_responses(options, state)

    data =
      dialogue
      |> dialogue_data(speaker, text, meta, state, responses)
      |> attribute_choice_block(state)

    {dialogue_id, state} = add_node(state, "dialogue", data)
    state = state |> track_speaker(speaker, dialogue) |> connect_many(incoming, dialogue_id)
    branch_speaker = state.current_speaker

    {branch_outgoing, branch_speakers, state} =
      Enum.reduce(Enum.zip(options, responses), {[], [], state}, fn {option, response}, {outgoing, speakers, acc} ->
        acc = %{acc | current_speaker: branch_speaker}
        {branch_outgoing, acc} = compile_items(option.body, [{dialogue_id, response["id"]}], acc)
        {outgoing ++ branch_outgoing, record_branch_speaker(speakers, branch_outgoing, acc), acc}
      end)

    merge_branches(branch_outgoing, merge_branch_speakers(state, branch_speakers))
  end

  defp build_responses(options, state) do
    Enum.map_reduce(options, state, fn option, acc ->
      {label, condition, acc} = build_response(option, acc)

      response = %{
        "id" => runtime_id("response", option.source, option.line, option.line_id),
        "text" => Expression.interpolate(label, :response),
        "import_yarn_source_text" => label,
        "condition" => condition,
        "instruction" => nil
      }

      {response, acc}
    end)
  end

  defp build_response(option, state) do
    case extract_option_condition(option.text) do
      {:ok, label, condition_expression} ->
        {condition, state} = build_response_condition(condition_expression, option, state)
        {label, condition, state}

      {:error, :unsupported_yarn_condition} ->
        state = add_issue(state, :unsupported_yarn_condition, option, :error)
        {option.text, Jason.encode!(fail_closed_condition()), state}
    end
  end

  defp build_response_condition(nil, _option, state), do: {nil, state}

  defp build_response_condition(expression, option, state) do
    case Expression.condition(expression) do
      {:ok, condition} ->
        {Jason.encode!(condition), state}

      {:error, _reason} ->
        {Jason.encode!(fail_closed_condition()), add_issue(state, :unsupported_yarn_condition, option, :error)}
    end
  end

  # A lone `<<if>>` is a boolean fork; an `<<elseif>>` chain is a switch. Both
  # exist in Storyarn's `condition` node — `switch_mode` swaps the fixed
  # true/false pins for one pin per case plus `default`, and the evaluator walks
  # the cases in order and halts on the first match
  # (`condition_node_evaluator.ex:93`), which is exactly Yarn's elseif
  # semantics. Emitting one switch node instead of a chain of N boolean nodes is
  # therefore faithful, not an approximation.
  defp compile_conditional([_only_branch] = branches, else_body, meta, incoming, state) do
    compile_condition_chain(branches, else_body, meta, incoming, state)
  end

  defp compile_conditional(branches, else_body, meta, incoming, state) do
    case parse_branch_conditions(branches) do
      {:ok, parsed} -> compile_condition_switch(parsed, else_body, incoming, state)
      :error -> compile_condition_chain(branches, else_body, meta, incoming, state)
    end
  end

  # Every case must parse before the switch is worth building: one unsupported
  # condition in the chain and the whole node would need a fail-closed case,
  # which reads worse than the boolean chain the fallback produces.
  defp parse_branch_conditions(branches) do
    branches
    |> Enum.reduce_while({:ok, []}, fn branch, {:ok, acc} ->
      case Expression.condition(branch.condition) do
        {:ok, condition} -> {:cont, {:ok, [{branch, condition} | acc]}}
        {:error, _reason} -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      :error -> :error
    end
  end

  defp compile_condition_switch(parsed, else_body, incoming, state) do
    blocks =
      parsed
      |> Enum.with_index()
      |> Enum.map(fn {{branch, condition}, index} -> switch_case_block(branch, condition, index, state) end)

    data = %{"condition" => %{"logic" => "any", "blocks" => blocks}, "switch_mode" => true}
    {node_id, state} = add_node(state, "condition", data)
    state = connect_many(state, incoming, node_id)
    branch_speaker = state.current_speaker

    {case_exits, case_speakers, state} =
      parsed
      |> Enum.zip(blocks)
      |> Enum.reduce({[], [], state}, fn {{branch, _condition}, block}, {exits, speakers, acc} ->
        acc = %{acc | current_speaker: branch_speaker}
        {branch_exits, acc} = compile_items(branch.body, [{node_id, block["id"]}], acc)
        {exits ++ branch_exits, record_branch_speaker(speakers, branch_exits, acc), acc}
      end)

    # No `<<else>>` leaves `default` carrying the fall-through, so the pin stays
    # connected either way and the node never reports a missing output.
    state = %{state | current_speaker: branch_speaker}
    {else_exits, state} = compile_items(else_body, [{node_id, "default"}], state)
    branch_speakers = record_branch_speaker(case_speakers, else_exits, state)
    merge_branches(case_exits ++ else_exits, merge_branch_speakers(state, branch_speakers))
  end

  # The block id doubles as the case's output pin, so it has to be unique within
  # the node: two branches testing the same expression would otherwise collide
  # into one pin. The branch index guarantees uniqueness.
  defp switch_case_block(branch, condition, index, state) do
    rules =
      case condition do
        %{"blocks" => [%{"rules" => rules} | _rest]} when is_list(rules) -> rules
        %{"rules" => rules} when is_list(rules) -> rules
        _other -> []
      end

    %{
      "id" => stable_id("condition_block", "#{state.flow_id}:#{index}:#{branch.condition}"),
      "type" => "block",
      "logic" => Map.get(condition, "logic", "all"),
      "rules" => rules
    }
  end

  defp compile_condition_chain(branches, else_body, meta, incoming, state) do
    branch_speaker = state.current_speaker

    {branch_exits, branch_speakers, false_incoming, state} =
      Enum.reduce(branches, {[], [], incoming, state}, fn branch, {exits, speakers, branch_incoming, acc} ->
        acc = %{acc | current_speaker: branch_speaker}
        branch_meta = Map.get(branch, :meta, meta)

        {condition, branch_incoming, acc} =
          case Expression.condition(branch.condition) do
            {:ok, condition} ->
              {condition, branch_incoming, acc}

            {:error, _reason} ->
              acc = add_issue(acc, :unsupported_yarn_condition, branch_meta, :error)

              {annotated_incoming, acc} =
                add_unsupported_annotation(
                  acc,
                  branch_incoming,
                  branch_meta,
                  yarn_command("if", branch.condition)
                )

              {fail_closed_condition(), annotated_incoming, acc}
          end

        {condition_id, acc} = add_node(acc, "condition", %{"condition" => condition, "switch_mode" => false})
        acc = connect_many(acc, branch_incoming, condition_id)
        {true_exits, acc} = compile_items(branch.body, [{condition_id, "true"}], acc)

        {
          exits ++ true_exits,
          record_branch_speaker(speakers, true_exits, acc),
          [{condition_id, "false"}],
          acc
        }
      end)

    state = %{state | current_speaker: branch_speaker}
    {else_exits, state} = compile_items(else_body, false_incoming, state)
    branch_speakers = record_branch_speaker(branch_speakers, else_exits, state)
    merge_branches(branch_exits ++ else_exits, merge_branch_speakers(state, branch_speakers))
  end

  # Branches converge by fanning their loose pins straight onto whatever node
  # comes next: `flow_connections` is unique per
  # (source_node, source_pin, target_node, target_pin), so one input pin accepts
  # any number of sources. An intermediate node would add nothing —
  # Storyarn's `hub` is a named jump target, not a join, and an unlabelled one
  # renders as a "0 jumps" dead end.
  defp merge_branches(branch_outgoing, state), do: {Enum.uniq(branch_outgoing), state}

  defp record_branch_speaker(speakers, [], _state), do: speakers
  defp record_branch_speaker(speakers, _outgoing, state), do: [state.current_speaker | speakers]

  defp merge_branch_speakers(state, speakers) do
    current_speaker =
      case Enum.uniq(speakers) do
        [speaker] -> speaker
        _ambiguous_or_terminal -> nil
      end

    %{state | current_speaker: current_speaker}
  end

  defp dialogue_data(text, speaker, original_text, meta, state, responses) do
    source_text =
      if is_binary(speaker),
        do: SpeakerClassifier.unescape_colons(original_text),
        else: text

    data = %{
      "speaker_sheet_id" => Map.get(state.speaker_sheet_ids, speaker),
      "text" => Expression.interpolate(text, :dialogue),
      # Keep one authored source alongside the rendered text. Explicit speaker
      # lines retain the complete line so review choices remain reversible;
      # ordinary and inherited dialogue already use their complete text here.
      "import_yarn_source_text" => source_text,
      "stage_directions" => "",
      "menu_text" => "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => runtime_id("dialogue", meta.source, meta.line, meta[:line_id]),
      "avatar_id" => nil,
      "responses" => responses
    }

    if is_binary(speaker) do
      Map.put(data, "import_yarn_speaker", speaker)
    else
      data
    end
  end

  defp track_speaker(state, speaker, _dialogue) when is_binary(speaker), do: %{state | current_speaker: speaker}

  # A synthetic, textless choice host belongs to the speaker flowing into it.
  # Authored speakerless dialogue is different: it explicitly breaks that
  # attribution, while commands between a speaker and a menu continue to keep
  # the speaker state unchanged.
  defp track_speaker(state, nil, ""), do: state
  defp track_speaker(state, _speaker, _authored_dialogue), do: %{state | current_speaker: nil}

  # A choice block whose options do not follow a line of their own — options
  # after an `<<if>>/<<endif>>`, or first in a Yarn node — still needs a node to
  # host the responses, and that node has no speaker prefix to parse. Attribute
  # it to the character speaking into it so the menu is not reported as a
  # speakerless dialogue. Keep the inherited speaker as review-only metadata so
  # create/preserve/map decisions can update this host along with the explicit
  # speaker lines instead of leaving an id for a sheet the review removed.
  defp attribute_choice_block(%{"import_yarn_speaker" => _speaker} = data, _state), do: data

  defp attribute_choice_block(%{"speaker_sheet_id" => nil, "text" => ""} = data, %{current_speaker: speaker} = state)
       when is_binary(speaker) do
    data
    |> Map.put("import_yarn_inherited_speaker", speaker)
    |> Map.put("speaker_sheet_id", Map.get(state.speaker_sheet_ids, speaker))
  end

  defp attribute_choice_block(data, _state), do: data

  defp extract_option_condition(text) do
    case Regex.run(~r/^(.*?)\s*<<if\s+(.+?)>>\s*$/i, text, capture: :all_but_first) do
      [label, condition] -> {:ok, String.trim(label), String.trim(condition)}
      _other -> if Regex.match?(~r/<<\s*if\b/i, text), do: {:error, :unsupported_yarn_condition}, else: {:ok, text, nil}
    end
  end

  defp add_unsupported_annotation(state, incoming, meta, command) do
    data = %{
      "text" => "Review imported Yarn Spinner command:\n#{command}",
      "color" => "#f59e0b",
      "import_source" => meta.source,
      "import_line" => meta.line
    }

    {node_id, state} = add_node(state, "annotation", data)

    # Annotations carry no edges, so record where the command sat in the graph.
    # `Layout` uses it to park the note near its context instead of on top of an
    # executable node.
    anchors = Enum.map(incoming, fn {source_id, _pin} -> source_id end)
    state = %{state | annotation_anchors: Map.put(state.annotation_anchors, node_id, anchors)}

    {incoming, state}
  end

  defp yarn_command(name, ""), do: "<<#{name}>>"
  defp yarn_command(name, args), do: "<<#{name} #{args}>>"

  defp add_issue(state, code, meta, severity \\ :warning) do
    %{state | issues: [new_issue(severity, code, meta) | state.issues]}
  end

  defp new_issue(severity, code, meta) do
    ImportIssue.new(severity, code,
      source: Map.get(meta, :source),
      line: Map.get(meta, :line)
    )
  end

  # Even though plans containing this condition are rejected before preview,
  # keep the normalized representation fail-closed as a defence in depth. A
  # missing variable never passes the `is_true` operator.
  defp fail_closed_condition do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => stable_id("condition_block", "unsupported_yarn_condition"),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => stable_id("condition_rule", "unsupported_yarn_condition"),
              "sheet" => "__storyarn_import_guard__",
              "variable" => "unsupported_yarn_condition",
              "operator" => "is_true",
              "value" => nil
            }
          ]
        }
      ]
    }
  end

  defp add_node(state, type, data) do
    id = stable_id("node", "#{state.flow_id}:#{state.next_index}:#{type}")
    node = node(id, type, data)
    {id, %{state | nodes: [node | state.nodes], next_index: state.next_index + 1}}
  end

  # Positions are left at the origin here and assigned by `Layout` once the whole
  # graph is known — placement needs each node's depth, which is not available
  # while the node is being created.
  defp node(id, type, data) do
    %{
      "id" => id,
      "type" => type,
      "position_x" => 0.0,
      "position_y" => 0.0,
      "source" => "manual",
      "data" => data
    }
  end

  defp connect_many(state, incoming, target_id) do
    Enum.reduce(incoming, state, fn {source_id, source_pin}, acc ->
      connection = %{
        "id" => stable_id("connection", "#{source_id}:#{source_pin}:#{target_id}"),
        "source_node_id" => source_id,
        "source_pin" => source_pin,
        "target_node_id" => target_id,
        "target_pin" => "input",
        "label" => nil
      }

      %{acc | connections: [connection | acc.connections]}
    end)
  end

  defp resolve_flow_ref(flow_refs, target) do
    Map.get(flow_refs, String.trim(target))
  end

  defp walk_items(items) do
    Enum.flat_map(items, fn
      {:options, options, _meta} = item ->
        [item | Enum.flat_map(options, &walk_items(&1.body))]

      {:if, branches, else_body, _meta} = item ->
        [item | Enum.flat_map(branches, &walk_items(&1.body))] ++ walk_items(else_body)

      item ->
        [item]
    end)
  end

  defp runtime_id(prefix, source, line, external_id) do
    hint =
      external_id
      |> to_string()
      |> String.replace(~r/[^A-Za-z0-9_-]/u, "_")
      |> String.trim("_")
      |> String.slice(0, 40)

    digest = digest("#{source}:#{line}:#{external_id}")
    if hint == "", do: "#{prefix}_#{digest}", else: "#{prefix}_#{hint}_#{digest}"
  end

  defp stable_id(prefix, value), do: "#{prefix}_#{digest(value)}"

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end
end
