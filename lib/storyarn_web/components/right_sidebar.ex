defmodule StoryarnWeb.Components.RightSidebar do
  @moduledoc """
  Generic right-side sliding panel for canvas editors (flow, scene).

  Always in the DOM. Visibility is controlled client-side by the RightSidebar
  JS hook (via inline `style.display`), so opening is instant — zero server
  round-trip. The hook pushes open/close events to the server so it can load
  content lazily and update the dock button active state.

  ## Usage

      <.right_sidebar
        id="my-panel"
        title="Panel Title"
        open_event="open_my_panel"
        close_event="close_my_panel"
      >
        <:content>
          <div :if={@panel_content_loaded}>
            Loaded content here
          </div>
        </:content>
      </.right_sidebar>

  To toggle, dispatch from the trigger button:

      phx-click={JS.dispatch("panel:toggle", to: "#my-panel")}
  """

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open_event, :string, default: nil
  attr :close_event, :string, required: true
  attr :width, :string, default: "320px"
  attr :phx_target, :string, default: nil
  attr :loading, :boolean, default: false, doc: "Show loading spinner instead of content"

  slot :inner_block, required: true
  slot :actions, doc: "Extra buttons rendered in the header between the title and close button"

  def right_sidebar(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="RightSidebar"
      data-right-panel
      data-open-event={@open_event}
      data-close-event={@close_event}
      data-phx-target={@phx_target}
      class={[
        "fixed flex flex-col overflow-hidden right-sidebar",
        "inset-0 z-[1030] bg-base-100",
        "xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3"
      ]}
      style={"--rs-width: #{@width}"}
    >
      <header class="flex items-center gap-2 px-3 py-2 border-b border-base-300 shrink-0">
        <h3 class="flex-1 text-sm font-semibold truncate">{@title}</h3>
        {render_slot(@actions)}
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          phx-click={Phoenix.LiveView.JS.dispatch("panel:close", to: "##{@id}")}
        >
          <.icon name="x" class="size-4" />
        </button>
      </header>
      <div class="flex-1 overflow-y-auto p-3">
        <div :if={@loading} class="flex items-center justify-center h-full">
          <span class="loading loading-spinner loading-md text-base-content/40"></span>
        </div>
        <div :if={!@loading}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
