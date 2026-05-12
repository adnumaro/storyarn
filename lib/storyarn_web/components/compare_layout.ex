defmodule StoryarnWeb.Components.CompareLayout do
  @moduledoc """
  LiveVue layout boundary for fullscreen version comparison and compact viewers.

  Compare routes are immersive inspection surfaces. The route LiveView owns data
  and actions; Vue owns the visual shell and receives public children through
  LiveVue injection slots.
  """

  use StoryarnWeb, :html

  attr :id, :string, default: "compare-layout"
  attr :flash, :map, required: true
  attr :socket, :any, required: true
  attr :panel_title, :string, default: nil
  attr :panel_open, :boolean, default: true
  attr :content_class, :string, default: "h-full overflow-hidden"

  slot :inner_block, required: true

  def compare(assigns) do
    ~H"""
    <div id="compare-layout-wrapper">
      <.vue
        v-component="live/layouts/compare/Layout"
        v-socket={@socket}
        id={@id}
        panel-title={@panel_title}
        panel-open={@panel_open}
        content-class={@content_class}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
