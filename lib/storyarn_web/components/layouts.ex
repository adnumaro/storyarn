defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS
  alias Storyarn.Analytics

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} socket={@socket} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue events)"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    assigns =
      assigns
      |> assign(:flash_messages, flash_messages(assigns.flash))
      |> assign(:network_flash, network_flash_messages())

    ~H"""
    <div
      id={@id}
      aria-live="polite"
      phx-disconnected={
        JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        |> show(".phx-client-error #client-error")
        |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        |> show(".phx-server-error #server-error")
      }
      phx-connected={
        hide("#client-error")
        |> JS.set_attribute({"hidden", ""}, to: "#client-error")
        |> hide("#server-error")
        |> JS.set_attribute({"hidden", ""}, to: "#server-error")
      }
    >
      <.vue
        v-component="live/layouts/flash/FlashGroup"
        v-socket={@socket}
        id={"#{@id}-content"}
        flash={@flash_messages}
        network={@network_flash}
      />
    </div>
    """
  end

  defp flash_messages(flash) do
    %{
      info: Phoenix.Flash.get(flash, :info),
      warning: Phoenix.Flash.get(flash, :warning),
      error: Phoenix.Flash.get(flash, :error)
    }
  end

  defp network_flash_messages do
    %{
      clientTitle: gettext("We can't find the internet"),
      serverTitle: gettext("Something went wrong!"),
      reconnecting: gettext("Attempting to reconnect")
    }
  end

  def posthog_frontend_config(assigns) do
    assigns
    |> current_scope_from_assigns()
    |> Analytics.frontend_config()
  end

  defp current_scope_from_assigns(%{current_scope: current_scope}), do: current_scope

  defp current_scope_from_assigns(%{conn: %{assigns: %{current_scope: current_scope}}}) do
    current_scope
  end

  defp current_scope_from_assigns(%{socket: %{assigns: %{current_scope: current_scope}}}) do
    current_scope
  end

  defp current_scope_from_assigns(_assigns), do: nil
end
