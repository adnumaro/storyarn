defmodule StoryarnWeb.FlowLive.Nodes.Condition.Node do
  @moduledoc """
  Condition node type definition.

  Evaluates conditions to route flow. Supports boolean (true/false) and
  switch mode (multiple labeled outputs).
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows.Condition

  def type, do: "condition"
  def icon_name, do: "git-branch"
  def label, do: gettext("Condition")

  def default_data do
    %{
      "condition" => %{"logic" => "all", "rules" => []},
      "switch_mode" => false
    }
  end

  def extract_form_data(data) do
    %{
      "condition" => data["condition"] || %{"logic" => "all", "rules" => []},
      "switch_mode" => data["switch_mode"] || false
    }
  end

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :sidebar
  def duplicate_data_cleanup(data), do: data

  # -- Condition-specific event handlers --

  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  @doc "Handles updates to the condition builder for condition nodes."
  def handle_update_condition_builder(params, socket) do
    handle_condition_node_update(socket, params)
  end

  @doc """
  Handles updates to response condition builders (used by dialogue responses).
  This is condition-building logic, so it lives here even though it's called
  for dialogue response conditions.
  """
  def handle_update_response_condition_builder(params, socket) do
    handle_response_condition_update(socket, params)
  end

  @doc "Toggles switch mode on a condition node."
  def handle_toggle_switch_mode(socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, fn data ->
        new_switch_mode = !(data["switch_mode"] || false)

        updated_condition =
          if new_switch_mode do
            condition = data["condition"] || Condition.new()
            rules = condition["rules"] || []

            updated_rules =
              Enum.map(rules, fn rule ->
                Map.put_new(rule, "label", "")
              end)

            Map.put(condition, "rules", updated_rules)
          else
            data["condition"]
          end

        data
        |> Map.put("switch_mode", new_switch_mode)
        |> Map.put("condition", updated_condition)
      end)
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp handle_condition_node_update(socket, params) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, fn data ->
        current_condition = data["condition"] || Condition.new()
        updated_condition = apply_condition_update(current_condition, params)
        Map.put(data, "condition", updated_condition)
      end)
    else
      {:noreply, socket}
    end
  end

  defp handle_response_condition_update(socket, params) do
    response_id = params["response-id"]
    node_id = params["node-id"]

    if node_id && response_id do
      NodeHelpers.persist_node_update(socket, node_id, fn data ->
        Map.update(data, "responses", [], fn responses ->
          Enum.map(responses, fn
            %{"id" => ^response_id} = resp ->
              current_condition = parse_response_condition(resp)
              updated_condition = apply_condition_update(current_condition, params)
              Map.put(resp, "condition", Condition.to_json(updated_condition))

            resp ->
              resp
          end)
        end)
      end)
    else
      {:noreply, socket}
    end
  end

  defp parse_response_condition(response) do
    raw_condition = response["condition"] || ""

    case Condition.parse(raw_condition) do
      :legacy -> Condition.new()
      nil -> Condition.new()
      cond_data -> cond_data
    end
  end

  defp apply_condition_update(current_condition, params) do
    cond do
      Map.has_key?(params, "logic") ->
        Condition.set_logic(current_condition, params["logic"])

      params["action"] == "add_rule" ->
        with_label = params["switch-mode"] == "true"
        Condition.add_rule(current_condition, with_label: with_label)

      params["action"] == "remove_rule" ->
        Condition.remove_rule(current_condition, params["rule-id"])

      true ->
        apply_rule_field_update(current_condition, params)
    end
  end

  defp apply_rule_field_update(current_condition, params) do
    target = params["_target"] || []
    target_field = List.first(target)

    rule_update =
      cond do
        target_field && String.starts_with?(target_field, "rule_sheet_") ->
          rule_id = String.replace_prefix(target_field, "rule_sheet_", "")
          {:sheet, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_variable_") ->
          rule_id = String.replace_prefix(target_field, "rule_variable_", "")
          {:variable, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_operator_") ->
          rule_id = String.replace_prefix(target_field, "rule_operator_", "")
          {:operator, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_value_") ->
          rule_id = String.replace_prefix(target_field, "rule_value_", "")
          {:value, rule_id, params[target_field]}

        target_field && String.starts_with?(target_field, "rule_label_") ->
          rule_id = String.replace_prefix(target_field, "rule_label_", "")
          {:label, rule_id, params[target_field]}

        true ->
          Enum.find_value(params, fn
            {"rule_sheet_" <> rule_id, value} -> {:sheet, rule_id, value}
            {"rule_variable_" <> rule_id, value} -> {:variable, rule_id, value}
            {"rule_operator_" <> rule_id, value} -> {:operator, rule_id, value}
            {"rule_value_" <> rule_id, value} -> {:value, rule_id, value}
            {"rule_label_" <> rule_id, value} -> {:label, rule_id, value}
            _ -> nil
          end)
      end

    case rule_update do
      {field, rule_id, value} ->
        Condition.update_rule(current_condition, rule_id, Atom.to_string(field), value)

      nil ->
        current_condition
    end
  end
end
