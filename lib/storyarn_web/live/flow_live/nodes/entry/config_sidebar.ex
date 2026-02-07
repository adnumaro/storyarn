defmodule StoryarnWeb.FlowLive.Nodes.Entry.ConfigSidebar do
  @moduledoc """
  Sidebar panel for entry nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

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
    ~H"""
    <div class="text-center py-4">
      <.icon name="play" class="size-8 text-success mx-auto mb-2" />
      <p class="text-sm text-base-content/60">
        {gettext("This is the entry point of the flow.")}
      </p>
      <p class="text-xs text-base-content/50 mt-2">
        {gettext("Connect this node to the first node in your flow.")}
      </p>
    </div>
    """
  end

  def wrap_in_form?, do: true
end
