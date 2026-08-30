defmodule Storyarn.Flows.References.Rules.StaleVariableReferenceData do
  @moduledoc """
  Applies current Sheet variable identities to Flow-owned node data.

  This rule deliberately preserves legacy Flow payload shapes. In particular,
  dialogue response conditions may remain maps or encoded JSON, structured
  assignments take precedence over the legacy `instruction` field, and
  malformed draft fragments are left untouched.
  """

  @type repair_reference :: %{
          required(:kind) => String.t(),
          required(:source_sheet) => String.t(),
          required(:source_variable) => String.t(),
          required(:current_shortcut) => String.t(),
          required(:current_variable) => String.t()
        }

  @doc "Returns the current table path represented by one persisted reference."
  @spec normalize_reference(map()) :: map()
  def normalize_reference(%{source_variable: source, current_variable: current} = reference)
      when is_binary(source) and is_binary(current) do
    case String.split(source, ".", parts: 3) do
      [_old_table, row_slug, column_slug] ->
        %{reference | current_variable: "#{current}.#{row_slug}.#{column_slug}"}

      _regular_or_malformed ->
        reference
    end
  end

  def normalize_reference(reference), do: reference

  @doc "Repairs stale variable identities without normalizing any other node data."
  @spec repair(String.t(), map(), [repair_reference()]) :: map()
  def repair("instruction", data, references) when is_map(data) and is_list(references) do
    assignments = data["assignments"] || []

    assignments =
      assignments
      |> repair_write_targets(Enum.filter(references, &(&1.kind == "write")))
      |> repair_read_sources(Enum.filter(references, &(&1.kind == "read")))

    Map.put(data, "assignments", assignments)
  end

  def repair("condition", data, references) when is_map(data) and is_list(references) do
    read_references = Enum.filter(references, &(&1.kind == "read"))
    condition = repair_condition(data["condition"], read_references)

    if condition == data["condition"], do: data, else: Map.put(data, "condition", condition)
  end

  def repair("dialogue", %{"responses" => responses} = data, references)
      when is_list(responses) and is_list(references) do
    read_references = Enum.filter(references, &(&1.kind == "read"))
    write_references = Enum.filter(references, &(&1.kind == "write"))

    repaired_responses =
      Enum.map(responses, &repair_dialogue_response(&1, write_references, read_references))

    if repaired_responses == responses,
      do: data,
      else: Map.put(data, "responses", repaired_responses)
  end

  def repair(_type, data, _references), do: data

  defp repair_dialogue_response(%{} = response, write_references, read_references) do
    response
    |> repair_dialogue_response_condition(read_references)
    |> repair_dialogue_response_assignments(write_references, read_references)
  end

  defp repair_dialogue_response(response, _write_references, _read_references), do: response

  defp repair_dialogue_response_condition(%{"condition" => %{} = condition} = response, read_references) do
    repaired_condition = repair_condition(condition, read_references)

    if repaired_condition == condition,
      do: response,
      else: Map.put(response, "condition", repaired_condition)
  end

  defp repair_dialogue_response_condition(%{"condition" => condition} = response, read_references)
       when is_binary(condition) and condition != "" do
    case Jason.decode(condition) do
      {:ok, %{} = decoded_condition} ->
        repaired_condition = repair_condition(decoded_condition, read_references)

        if repaired_condition == decoded_condition,
          do: response,
          else: Map.put(response, "condition", Jason.encode!(repaired_condition))

      _invalid ->
        response
    end
  end

  defp repair_dialogue_response_condition(response, _read_references), do: response

  defp repair_dialogue_response_assignments(
         %{"instruction_assignments" => [_assignment | _rest] = assignments} = response,
         write_references,
         read_references
       ) do
    repaired_assignments = repair_assignments(assignments, write_references, read_references)

    if repaired_assignments == assignments,
      do: response,
      else: Map.put(response, "instruction_assignments", repaired_assignments)
  end

  defp repair_dialogue_response_assignments(
         %{"instruction_assignments" => invalid} = response,
         _write_references,
         _read_references
       )
       when invalid not in [nil, []], do: response

  defp repair_dialogue_response_assignments(response, write_references, read_references) do
    repair_legacy_response_assignments(response, write_references, read_references)
  end

  defp repair_legacy_response_assignments(%{"instruction" => instruction} = response, write_references, read_references)
       when is_binary(instruction) and instruction != "" do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) ->
        repaired_assignments = repair_assignments(assignments, write_references, read_references)

        if repaired_assignments == assignments,
          do: response,
          else: Map.put(response, "instruction", Jason.encode!(repaired_assignments))

      _invalid ->
        response
    end
  end

  defp repair_legacy_response_assignments(response, _write_references, _read_references), do: response

  defp repair_assignments(assignments, write_references, read_references) do
    assignments
    |> repair_write_targets(write_references)
    |> repair_read_sources(read_references)
  end

  defp repair_condition(%{"blocks" => blocks} = condition, read_references) when is_list(blocks) do
    Map.put(condition, "blocks", Enum.map(blocks, &repair_block(&1, read_references)))
  end

  defp repair_condition(condition, _read_references), do: condition

  defp repair_write_targets(assignments, write_references) when is_list(assignments) do
    Enum.map(assignments, &repair_write_target(&1, write_references))
  end

  defp repair_write_targets(assignments, _write_references), do: assignments

  defp repair_write_target(%{} = assignment, write_references) do
    matching_reference =
      Enum.find(write_references, fn reference ->
        reference.source_sheet == assignment["sheet"] and
          reference.source_variable == assignment["variable"]
      end)

    if matching_reference do
      assignment
      |> Map.put("sheet", matching_reference.current_shortcut)
      |> Map.put("variable", matching_reference.current_variable)
    else
      assignment
    end
  end

  defp repair_write_target(assignment, _write_references), do: assignment

  defp repair_read_sources(assignments, read_references) when is_list(assignments) do
    Enum.map(assignments, &repair_read_source(&1, read_references))
  end

  defp repair_read_sources(assignments, _read_references), do: assignments

  defp repair_read_source(%{"value_type" => "variable_ref"} = assignment, read_references) do
    matching_reference =
      Enum.find(read_references, fn reference ->
        reference.source_sheet == assignment["value_sheet"] and
          reference.source_variable == assignment["value"]
      end)

    if matching_reference do
      assignment
      |> Map.put("value_sheet", matching_reference.current_shortcut)
      |> Map.put("value", matching_reference.current_variable)
    else
      assignment
    end
  end

  defp repair_read_source(assignment, _read_references), do: assignment

  defp repair_condition_rules(rules, read_references) when is_list(rules) do
    Enum.map(rules, &repair_condition_rule(&1, read_references))
  end

  defp repair_condition_rules(rules, _read_references), do: rules

  defp repair_condition_rule(%{} = rule, read_references) do
    matching_reference =
      Enum.find(read_references, fn reference ->
        reference.source_sheet == rule["sheet"] and
          reference.source_variable == rule["variable"]
      end)

    if matching_reference do
      rule
      |> Map.put("sheet", matching_reference.current_shortcut)
      |> Map.put("variable", matching_reference.current_variable)
    else
      rule
    end
  end

  defp repair_condition_rule(rule, _read_references), do: rule

  defp repair_block(%{"type" => "block", "rules" => rules} = block, read_references) when is_list(rules) do
    Map.put(block, "rules", repair_condition_rules(rules, read_references))
  end

  defp repair_block(%{"type" => "group", "blocks" => inner_blocks} = group, read_references) when is_list(inner_blocks) do
    Map.put(group, "blocks", Enum.map(inner_blocks, &repair_block(&1, read_references)))
  end

  defp repair_block(block, _read_references), do: block
end
