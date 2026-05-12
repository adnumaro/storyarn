defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  # App layout — delegates to AppLayout module (Vue + shadcn-vue)
  defdelegate app(assigns), to: StoryarnWeb.Components.AppLayout

  # Workspace layout — static sidebar layout for workspaces dashboard
  defdelegate workspace(assigns), to: StoryarnWeb.Components.WorkspaceLayout

  @doc """
  Renders a chromeless canvas layout for version comparison mode.

  No project menu, tool switcher, or user menu. Optional collapsible
  side panel for layer controls or similar content. Always canvas mode.

  ## Examples

      <Layouts.compare flash={@flash} panel_title="Layers" panel_open={@main_sidebar_open}>
        <:panel>
          Layer controls here
        </:panel>
        Canvas content here
      </Layouts.compare>
  """
  attr :flash, :map, required: true
  attr :panel_title, :string, default: nil, doc: "title shown in the side panel header"
  attr :panel_open, :boolean, default: true, doc: "whether the side panel is open"

  slot :panel, doc: "optional side panel content (e.g. layer controls)"
  slot :inner_block, required: true

  def compare(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden relative bg-background">
      <%!-- Floating button to reopen panel when collapsed --%>
      <button
        :if={@panel != [] && !@panel_open}
        type="button"
        phx-click="main_sidebar_toggle"
        class="fixed top-3 left-3 z-[1020] surface-panel p-1"
        title={gettext("Show panel")}
      >
        <span class="inline-flex items-center justify-center size-8 rounded-md hover:bg-accent transition-colors">
          <.icon name="panel-left" class="size-4" />
        </span>
      </button>

      <%!-- Collapsible side panel --%>
      <div
        :if={@panel != []}
        id="compare-panel"
        class={[
          "fixed left-3 top-3 bottom-3 z-[1010] w-52 flex flex-col surface-panel overflow-hidden",
          "transition-all duration-200",
          if(@panel_open,
            do: "translate-x-0 opacity-100",
            else: "-translate-x-[calc(100%+0.75rem)] opacity-0 pointer-events-none"
          )
        ]}
      >
        <%!-- Panel header with title + collapse button --%>
        <div class="flex items-center justify-between px-2.5 py-2 border-b border-border">
          <span
            :if={@panel_title}
            class="text-xs font-medium text-muted-foreground flex items-center gap-1.5"
          >
            {@panel_title}
          </span>
          <button
            type="button"
            phx-click="main_sidebar_toggle"
            class="inline-flex items-center justify-center size-7 rounded-md hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
            title={gettext("Close panel")}
          >
            <.icon name="panel-left-close" class="size-3.5" />
          </button>
        </div>

        <%!-- Panel content (scrollable) --%>
        <div class="flex-1 overflow-y-auto p-2">
          {render_slot(@panel)}
        </div>
      </div>

      <%!-- Main content area (always canvas mode) --%>
      <main id="main-content" class="h-full overflow-hidden">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      data-slot="toaster"
      class="fixed bottom-4 right-4 z-[2000] flex flex-col gap-2 w-full max-w-sm pointer-events-none [&>*]:pointer-events-auto"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-1.5">
          {gettext("Attempting to reconnect")}
          <.icon name="loader-circle" class="size-4 motion-safe:animate-spin" />
        </span>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-1.5">
          {gettext("Attempting to reconnect")}
          <.icon name="loader-circle" class="size-4 motion-safe:animate-spin" />
        </span>
      </.flash>
    </div>
    """
  end
end
