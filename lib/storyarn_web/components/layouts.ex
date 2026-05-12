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

  # Workspace layout — static sidebar layout for workspaces dashboard
  defdelegate workspace(assigns), to: StoryarnWeb.Components.WorkspaceLayout

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
