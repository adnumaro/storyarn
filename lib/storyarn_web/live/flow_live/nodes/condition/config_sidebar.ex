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
  attr :all_pages, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    raw_condition = assigns.node.data["condition"]

    condition_data =
      case raw_condition do
        nil -> Condition.new()
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
          <span class="label-text">{gettext("Switch mode")}</span>
        </label>
        <p class="text-xs text-base-content/50 ml-12">
          <%= if @switch_mode do %>
            {gettext("Each condition creates an output. First match wins.")}
          <% else %>
            {gettext("Evaluates all conditions → True or False.")}
          <% end %>
        </p>
      </div>

      <%!-- Visual condition builder --%>
      <div class="space-y-3">
        <label class="label">
          <span class="label-text text-xs">
            <%= if @switch_mode do %>
              {gettext("Conditions (each = output)")}
            <% else %>
              {gettext("Condition")}
            <% end %>
          </span>
        </label>
        <.condition_builder
          id={"condition-builder-#{@node.id}"}
          condition={@condition_data}
          variables={@project_variables}
          on_change="update_condition_builder"
          can_edit={@can_edit}
          show_expression_toggle={false}
          expression_mode={false}
          raw_expression=""
          wrap_in_form={true}
          switch_mode={@switch_mode}
        />
        <p :if={@condition_data["rules"] == [] && !@switch_mode} class="text-xs text-base-content/50">
          {gettext("Add rules to define when to route to True/False.")}
        </p>
        <p :if={@condition_data["rules"] == [] && @switch_mode} class="text-xs text-base-content/50">
          {gettext("Add conditions. Each one creates a separate output.")}
        </p>
      </div>

      <%!-- Output info --%>
      <div class="bg-base-200 rounded-lg p-3 text-xs">
        <p class="font-medium mb-1">{gettext("Outputs:")}</p>
        <%= if @switch_mode do %>
          <ul class="list-disc list-inside text-base-content/70 space-y-1">
            <li :for={rule <- @condition_data["rules"]}>
              {rule["label"] || gettext("(no label)")}
            </li>
            <li class="text-base-content/50 italic">{gettext("Default (no match)")}</li>
          </ul>
          <p :if={@condition_data["rules"] == []} class="text-base-content/50 italic">
            {gettext("Default (no match)")}
          </p>
        <% else %>
          <ul class="list-disc list-inside text-base-content/70">
            <li>{gettext("True")}</li>
            <li>{gettext("False")}</li>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end

  def wrap_in_form?, do: false
end
