defmodule StoryarnWeb.Components.CollaborationComponents do
  @moduledoc """
  Components for real-time collaboration features in the Flow Editor.

  Includes:
  - Collaboration toasts for remote change notifications
  """
  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders a toast notification for collaboration events.

  ## Examples

      <.collab_toast
        :if={@collab_toast}
        action={@collab_toast.action}
        user_email={@collab_toast.user_email}
        user_color={@collab_toast.user_color}
      />
  """
  attr :action, :atom, required: true, doc: "The action that occurred"
  attr :user_email, :string, required: true, doc: "Email of user who performed action"
  attr :user_color, :string, required: true, doc: "User's assigned color"
  attr :details, :string, default: nil, doc: "Optional additional details"

  def collab_toast(assigns) do
    message = action_message(assigns.action, assigns.details)
    assigns = assign(assigns, :message, message)

    ~H"""
    <div
      class="fixed bottom-4 left-4 z-50 animate-slide-in-left"
      role="status"
      aria-live="polite"
      phx-mounted={
        JS.transition(
          {"transition-opacity duration-300", "opacity-0", "opacity-100"},
          time: 300
        )
      }
    >
      <div class="alert shadow-lg max-w-sm" style={"border-left: 4px solid #{@user_color};"}>
        <div class="flex items-center gap-2">
          <div
            class="size-2 rounded-full shrink-0"
            style={"background-color: #{@user_color};"}
          >
          </div>
          <div class="text-sm">
            <span class="font-medium">{get_email_name(@user_email)}</span>
            <span class="text-muted-foreground">{@message}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp action_message(:node_added, _), do: gettext("added a node")
  defp action_message(:node_deleted, _), do: gettext("deleted a node")
  defp action_message(:node_moved, _), do: gettext("moved a node")
  defp action_message(:node_updated, _), do: gettext("updated a node")
  defp action_message(:node_restored, _), do: gettext("restored a node")
  defp action_message(:node_locked, _), do: gettext("is editing a node")
  defp action_message(:node_unlocked, _), do: gettext("finished editing")
  defp action_message(:flow_refresh, _), do: gettext("updated the flow")
  defp action_message(:connection_added, _), do: gettext("added a connection")
  defp action_message(:connection_deleted, _), do: gettext("deleted a connection")
  defp action_message(:user_joined, _), do: gettext("joined the flow")
  defp action_message(:user_left, _), do: gettext("left the flow")
  defp action_message(_, _), do: gettext("made a change")

  @spec get_email_name(any()) :: String.t()
  defp get_email_name(email) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp get_email_name(_), do: gettext("Someone")
end
