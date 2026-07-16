defmodule Storyarn.Imports.Parsers.Yarn.Normalizer do
  @moduledoc false

  alias Storyarn.Imports.ImportIssue
  alias Storyarn.Imports.Parsers.Yarn.Expression
  alias Storyarn.Shared.NameNormalizer

  @max_issues 1_000

  @spec normalize([map()]) :: {:ok, map(), [ImportIssue.t()], map()} | {:error, atom()}
  def normalize(documents) when is_list(documents) do
    with :ok <- validate_titles(documents) do
      {declarations, declaration_issues} = collect_declarations(documents)
      references = collect_references(documents)
      condition_references = collect_condition_references(documents)
      assignment_targets = collect_assignment_targets(documents)

      {variables, variable_issues} =
        merge_variables(declarations, references, condition_references, assignment_targets)

      speakers = collect_speakers(documents)
      {sheets, speaker_sheet_ids} = build_sheets(variables, speakers)
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

      issues = limit_issues(declaration_issues ++ variable_issues ++ flow_issues)

      data = %{
        "storyarn_version" => "1.0.0",
        "export_version" => "1.0.0",
        "project" => %{
          "name" => "Yarn Spinner Import",
          "settings" => %{"import_source" => "yarn_spinner"}
        },
        "sheets" => sheets,
        "flows" => flows,
        "scenes" => [],
        "screenplays" => []
      }

      metadata = %{
        flow_count: length(flows),
        sheet_count: length(sheets),
        variable_count: length(variables),
        warning_count: Enum.count(issues, &(&1.severity == :warning)),
        error_count: Enum.count(issues, &(&1.severity == :error))
      }

      {:ok, data, issues, metadata}
    end
  end

  defp validate_titles(documents) do
    duplicate? =
      documents
      |> Enum.map(& &1.title)
      |> Enum.frequencies()
      |> Enum.any?(fn {_title, count} -> count > 1 end)

    if duplicate?, do: {:error, :duplicate_yarn_node_title}, else: :ok
  end

  defp limit_issues(issues) do
    {errors, warnings} = Enum.split_with(issues, &(&1.severity == :error))
    Enum.take(errors ++ warnings, @max_issues)
  end

  defp collect_declarations(documents) do
    {declarations, issues} =
      documents
      |> Enum.flat_map(&walk_items(&1.body))
      |> Enum.reduce({%{}, []}, fn
        {:command, "declare", args, meta}, {declarations, issues} ->
          case Expression.declaration(args) do
            {:ok, declaration} ->
              declaration = Map.put(declaration, :meta, meta)
              {Map.put_new(declarations, declaration.variable, declaration), issues}

            {:error, _reason} ->
              {declarations, [new_issue(:error, :unsupported_yarn_declaration, meta) | issues]}
          end

        _item, acc ->
          acc
      end)

    {declarations, Enum.reverse(issues)}
  end

  defp collect_references(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(fn
      {:line, text, _meta} -> Expression.referenced_variables(text)
      {:command, _name, args, _meta} -> Expression.referenced_variables(args)
      {:if, branches, _else_body, _meta} -> Enum.flat_map(branches, &Expression.referenced_variables(&1.condition))
      {:options, options, _meta} -> Enum.flat_map(options, &Expression.referenced_variables(&1.text))
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

  defp collect_speakers(documents) do
    documents
    |> Enum.flat_map(&walk_items(&1.body))
    |> Enum.flat_map(fn
      {:line, text, _meta} ->
        case split_speaker(text) do
          {speaker, _dialogue} when is_binary(speaker) -> [speaker]
          _other -> []
        end

      _item ->
        []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp build_sheets(variables, speakers) do
    variable_sheet = if variables == [], do: [], else: [build_variable_sheet(variables)]
    used = if variables == [], do: MapSet.new(), else: MapSet.new(["yarn"])

    {speaker_sheets, speaker_ids, _used} =
      speakers
      |> Enum.with_index(length(variable_sheet))
      |> Enum.reduce({[], %{}, used}, fn {speaker, index}, {sheets, ids, used_shortcuts} ->
        shortcut = unique_shortcut(NameNormalizer.shortcutify(speaker), used_shortcuts)
        id = stable_id("speaker_sheet", speaker)

        sheet = %{
          "id" => id,
          "name" => speaker,
          "shortcut" => shortcut,
          "description" => "Imported Yarn Spinner character",
          "color" => "#8b5cf6",
          "position" => index,
          "blocks" => []
        }

        {[sheet | sheets], Map.put(ids, speaker, id), MapSet.put(used_shortcuts, shortcut)}
      end)

    {variable_sheet ++ Enum.reverse(speaker_sheets), speaker_ids}
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
          "config" => %{"label" => variable.variable},
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
        base = if base == "", do: "yarn-flow-#{index + 1}", else: base
        shortcut = unique_shortcut(base, used)
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
      nodes: [node(entry_id, "entry", %{"label" => "Start"}, 0)],
      connections: [],
      next_index: 1,
      issues: [],
      flow_refs: flow_refs,
      speaker_sheet_ids: speaker_sheet_ids
    }

    {outgoing, state} = compile_items(document.body, [{entry_id, "output"}], state)

    state =
      if outgoing == [] do
        state
      else
        {exit_id, state} = add_node(state, "exit", %{"label" => "End", "exit_mode" => "terminal"})
        connect_many(state, outgoing, exit_id)
      end

    flow = %{
      "id" => flow_id,
      "name" => document.headers["title"] || document.title,
      "shortcut" => shortcut,
      "description" => document.headers["description"],
      "position" => position,
      "is_main" => position == 0,
      "settings" => %{"import_source" => "yarn_spinner"},
      "nodes" => Enum.reverse(state.nodes),
      "connections" => Enum.reverse(state.connections)
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
    {speaker, dialogue} = split_speaker(text)

    data = dialogue_data(dialogue, speaker, meta, state, [])
    {node_id, state} = add_node(state, "dialogue", data)
    state = connect_many(state, incoming, node_id)
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

  defp compile_items([{:command, "return", _args, _meta} | rest], incoming, state) do
    {node_id, state} = add_node(state, "exit", %{"label" => "Return", "exit_mode" => "caller_return"})
    state = connect_many(state, incoming, node_id)
    compile_items(rest, [], state)
  end

  defp compile_items([{:command, "stop", _args, _meta} | rest], incoming, state) do
    {node_id, state} = add_node(state, "exit", %{"label" => "Stop", "exit_mode" => "terminal"})
    state = connect_many(state, incoming, node_id)
    compile_items(rest, [], state)
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
    {speaker, dialogue} = split_speaker(text)
    {responses, state} = build_responses(options, state)
    data = dialogue_data(dialogue, speaker, meta, state, responses)
    {dialogue_id, state} = add_node(state, "dialogue", data)
    state = connect_many(state, incoming, dialogue_id)

    {branch_outgoing, state} =
      Enum.reduce(Enum.zip(options, responses), {[], state}, fn {option, response}, {outgoing, acc} ->
        {branch_outgoing, acc} = compile_items(option.body, [{dialogue_id, response["id"]}], acc)
        {outgoing ++ branch_outgoing, acc}
      end)

    merge_branches(branch_outgoing, state)
  end

  defp build_responses(options, state) do
    Enum.map_reduce(options, state, fn option, acc ->
      {label, condition, acc} = build_response(option, acc)

      response = %{
        "id" => runtime_id("response", option.source, option.line, option.line_id),
        "text" => Expression.interpolate(label, :response),
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

  defp compile_conditional(branches, else_body, meta, incoming, state) do
    {branch_exits, false_incoming, state} =
      Enum.reduce(branches, {[], incoming, state}, fn branch, {exits, branch_incoming, acc} ->
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
        {exits ++ true_exits, [{condition_id, "false"}], acc}
      end)

    {else_exits, state} = compile_items(else_body, false_incoming, state)
    merge_branches(branch_exits ++ else_exits, state)
  end

  defp merge_branches([], state), do: {[], state}

  defp merge_branches(branch_outgoing, state) do
    {hub_id, state} = add_node(state, "hub", %{"hub_id" => stable_id("hub", "#{state.flow_id}:#{state.next_index}")})
    state = connect_many(state, branch_outgoing, hub_id)
    {[{hub_id, "output"}], state}
  end

  defp dialogue_data(text, speaker, meta, state, responses) do
    %{
      "speaker_sheet_id" => Map.get(state.speaker_sheet_ids, speaker),
      "text" => Expression.interpolate(text, :dialogue),
      "stage_directions" => "",
      "menu_text" => "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => runtime_id("dialogue", meta.source, meta.line, meta[:line_id]),
      "avatar_id" => nil,
      "responses" => responses
    }
  end

  defp split_speaker(text) do
    case Regex.run(~r/^([\p{L}\p{N}_][\p{L}\p{N} _.'-]{0,59}):\s+(.+)$/u, text, capture: :all_but_first) do
      [speaker, dialogue] ->
        if String.downcase(speaker) in ["http", "https"],
          do: {nil, text},
          else: {String.trim(speaker), dialogue}

      _other ->
        {nil, text}
    end
  end

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
    state = connect_many(state, incoming, node_id)
    {[{node_id, "output"}], state}
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
    node = node(id, type, data, state.next_index)
    {id, %{state | nodes: [node | state.nodes], next_index: state.next_index + 1}}
  end

  defp node(id, type, data, index) do
    %{
      "id" => id,
      "type" => type,
      "position_x" => 80.0 + rem(index, 4) * 320.0,
      "position_y" => 80.0 + div(index, 4) * 220.0,
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
    target = String.trim(target)

    Map.get(flow_refs, target) ||
      Enum.find_value(flow_refs, fn {title, id} ->
        if NameNormalizer.shortcutify(title) == NameNormalizer.shortcutify(target), do: id
      end)
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

  defp unique_shortcut("", used), do: unique_shortcut("character", used)

  defp unique_shortcut(base, used) do
    if MapSet.member?(used, base), do: next_unique_shortcut(base, used), else: base
  end

  defp next_unique_shortcut(base, used) do
    2
    |> Stream.iterate(&(&1 + 1))
    |> Enum.find_value(fn suffix ->
      candidate = "#{base}-#{suffix}"
      if MapSet.member?(used, candidate), do: nil, else: candidate
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
