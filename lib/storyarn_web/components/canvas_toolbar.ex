defmodule StoryarnWeb.Components.CanvasToolbar do
  @moduledoc """
  Shared floating toolbar wrapper for canvas editors (flow, scene).

  Handles the outer positioning container, visibility toggling via CSS class,
  and the CanvasToolbar LiveView hook for repositioning after content patches.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :canvas_id, :string, required: true
  attr :visible, :boolean, default: false
  attr :z_class, :string, default: "z-30"

  slot :inner_block, required: true

  def canvas_toolbar(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CanvasToolbar"
      data-canvas-id={@canvas_id}
      class={["absolute canvas-toolbar", @z_class]}
    >
      <div :if={@visible} class="floating-toolbar">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
