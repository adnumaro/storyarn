defmodule StoryarnWeb.FlowLive.Nodes.Condition.ConfigSidebar do
  @moduledoc """
  Sidebar panel for condition nodes.

  Renders: switch mode toggle, condition builder, and output info.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.ConditionBuilder

  alias Storyarn.Flows.Condition

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :project, :map, required: true
  attr :current_user, :map, required: true
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    raw_condition = assigns.node.data["condition"]

    condition_data =
      case raw_condition do
        nil -> Condition.new()
        %{"logic" => _, "blocks" => _} = cond_data -> cond_data
        %{"logic" => _, "rules" => _} = cond_data -> cond_data
        _ -> Condition.new()
      end

    switch_mode = assigns.node.data["switch_mode"] || false

    assigns =
      assigns |> assign(:condition_data, condition_data) |> assign(:switch_mode, switch_mode)

    ~H"""
    <div class="space-y-4">
      <%!-- Switch mode toggle --%>
      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-3">
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-primary"
            checked={@switch_mode}
            phx-click="toggle_switch_mode"
            disabled={!@can_edit}
          />
          <span class="label-text">{dgettext("flows", "Switch mode")}</span>
        </label>
        <p class="text-xs text-base-content/50 ml-12">
          <%= if @switch_mode do %>
            {dgettext("flows", "Each condition creates an output. First match wins.")}
          <% else %>
            {dgettext("flows", "Evaluates all conditions → True or False.")}
          <% end %>
        </p>
      </div>

      <%!-- Visual condition builder --%>
      <div class="space-y-3">
        <label class="label">
          <span class="label-text text-xs">
            <%= if @switch_mode do %>
              {dgettext("flows", "Conditions (each = output)")}
            <% else %>
              {dgettext("flows", "Condition")}
            <% end %>
          </span>
        </label>
        <.condition_builder
          id={"condition-builder-#{@node.id}"}
          condition={@condition_data}
          variables={@project_variables}
          can_edit={@can_edit}
          switch_mode={@switch_mode}
        />
        <p :if={!Condition.has_rules?(@condition_data) && !@switch_mode} class="text-xs text-base-content/50">
          {dgettext("flows", "Add rules to define when to route to True/False.")}
        </p>
        <p :if={!Condition.has_rules?(@condition_data) && @switch_mode} class="text-xs text-base-content/50">
          {dgettext("flows", "Add conditions. Each one creates a separate output.")}
        </p>
      </div>

      <%!-- Output info --%>
      <div class="bg-base-200 rounded-lg p-3 text-xs">
        <p class="font-medium mb-1">{dgettext("flows", "Outputs:")}</p>
        <%= if @switch_mode do %>
          <ul class="list-disc list-inside text-base-content/70 space-y-1">
            <li :for={item <- switch_cases(@condition_data)}>
              {item["label"] || dgettext("flows", "(no label)")}
            </li>
            <li class="text-base-content/50 italic">{dgettext("flows", "Default (no match)")}</li>
          </ul>
          <p :if={switch_cases(@condition_data) == []} class="text-base-content/50 italic">
            {dgettext("flows", "Default (no match)")}
          </p>
        <% else %>
          <ul class="list-disc list-inside text-base-content/70">
            <li>{dgettext("flows", "True")}</li>
            <li>{dgettext("flows", "False")}</li>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end

  defp switch_cases(%{"blocks" => blocks}) when is_list(blocks), do: blocks
  defp switch_cases(%{"rules" => rules}) when is_list(rules), do: rules
  defp switch_cases(_), do: []

  def wrap_in_form?, do: false
end
