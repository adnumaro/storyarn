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
  def label, do: dgettext("flows", "Condition")

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

  @doc "Handles full-state push from the JS condition builder hook."
  def handle_update_condition_builder(%{"condition" => condition_data}, socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, fn data ->
        Map.put(data, "condition", Condition.sanitize(condition_data))
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_update_condition_builder(_params, socket) do
    {:noreply, socket}
  end

  @doc "Handles full-state push from JS hook for response conditions."
  def handle_update_response_condition_builder(
        %{"condition" => condition_data, "response-id" => response_id, "node-id" => node_id},
        socket
      ) do
    if node_id && response_id do
      NodeHelpers.persist_node_update(socket, node_id, fn data ->
        update_response_condition(data, response_id, condition_data)
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_update_response_condition_builder(_params, socket) do
    {:noreply, socket}
  end

  @doc "Toggles switch mode on a condition node."
  def handle_toggle_switch_mode(socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, &toggle_switch_data/1)
    else
      {:noreply, socket}
    end
  end

  # -- Private helpers --

  defp update_response_condition(data, response_id, condition_data) do
    Map.update(data, "responses", [], fn responses ->
      Enum.map(responses, fn
        %{"id" => ^response_id} = resp ->
          sanitized = Condition.sanitize(condition_data)
          Map.put(resp, "condition", Condition.to_json(sanitized))

        resp ->
          resp
      end)
    end)
  end

  defp toggle_switch_data(data) do
    new_switch_mode = !(data["switch_mode"] || false)
    updated_condition = maybe_add_labels(data["condition"], new_switch_mode)

    data
    |> Map.put("switch_mode", new_switch_mode)
    |> Map.put("condition", updated_condition)
  end

  defp maybe_add_labels(condition, true) do
    condition = condition || Condition.new()
    rules = condition["rules"] || []
    updated_rules = Enum.map(rules, fn rule -> Map.put_new(rule, "label", "") end)
    Map.put(condition, "rules", updated_rules)
  end

  defp maybe_add_labels(condition, false), do: condition
end
