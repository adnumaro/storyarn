defmodule StoryarnWeb.FlowLive.Handlers.ConditionEventHandlers do
  @moduledoc """
  Handles condition builder events for the flow editor LiveView.

  Responsible for: condition node builder updates, response condition builder
  updates, and switch mode toggling.
  Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias Storyarn.Flows.Condition
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.ResponseHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_update_condition_builder(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_condition_builder(params, socket) do
    handle_condition_node_update(socket, params)
  end

  @spec handle_update_response_condition_builder(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_response_condition_builder(params, socket) do
    handle_response_condition_update(socket, params)
  end

  @doc """
  Handles the update_node_data event when it contains response condition builder fields.
  Called from show.ex when the event params indicate response condition fields.
  """
  @spec handle_response_condition_from_form(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_response_condition_from_form(params, socket) do
    handle_response_condition_update(socket, params)
  end

  @spec handle_toggle_switch_mode(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_switch_mode(socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      current_switch_mode = node.data["switch_mode"] || false
      new_switch_mode = !current_switch_mode

      # When switching to switch mode, add labels to existing rules
      updated_condition =
        if new_switch_mode do
          condition = node.data["condition"] || Condition.new()
          rules = condition["rules"] || []

          updated_rules =
            Enum.map(rules, fn rule ->
              Map.put_new(rule, "label", "")
            end)

          Map.put(condition, "rules", updated_rules)
        else
          node.data["condition"]
        end

      updated_data =
        node.data
        |> Map.put("switch_mode", new_switch_mode)
        |> Map.put("condition", updated_condition)

      case Flows.update_node_data(node, updated_data) do
        {:ok, updated_node, _meta} ->
          form = FormHelpers.node_data_to_form(updated_node)
          schedule_save_status_reset()

          {:noreply,
           socket
           |> reload_flow_data()
           |> assign(:selected_node, updated_node)
           |> assign(:node_form, form)
           |> assign(:save_status, :saved)
           |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp handle_condition_node_update(socket, params) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      current_condition = node.data["condition"] || Condition.new()
      updated_condition = apply_condition_update(current_condition, params)

      updated_data = Map.put(node.data, "condition", updated_condition)

      case Flows.update_node_data(node, updated_data) do
        {:ok, updated_node, _meta} ->
          form = FormHelpers.node_data_to_form(updated_node)
          schedule_save_status_reset()

          {:noreply,
           socket
           |> reload_flow_data()
           |> assign(:selected_node, updated_node)
           |> assign(:node_form, form)
           |> assign(:save_status, :saved)
           |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_response_condition_update(socket, params) do
    response_id = params["response-id"]
    node_id = params["node-id"]

    case get_response_for_update(socket, node_id, response_id) do
      {:ok, response} ->
        current_condition = parse_response_condition(response)
        updated_condition = apply_condition_update(current_condition, params)
        new_condition_string = Condition.to_json(updated_condition)

        ResponseHelpers.update_response_field(
          socket,
          node_id,
          response_id,
          "condition",
          new_condition_string
        )

      :error ->
        {:noreply, socket}
    end
  end

  defp get_response_for_update(_socket, nil, _response_id), do: :error
  defp get_response_for_update(_socket, _node_id, nil), do: :error

  defp get_response_for_update(socket, node_id, response_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    case Enum.find(responses, fn r -> r["id"] == response_id end) do
      nil -> :error
      response -> {:ok, response}
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
        target_field && String.starts_with?(target_field, "rule_page_") ->
          rule_id = String.replace_prefix(target_field, "rule_page_", "")
          {:page, rule_id, params[target_field]}

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
            {"rule_page_" <> rule_id, value} -> {:page, rule_id, value}
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
