defmodule StoryarnWeb.CollaborationComponents do
  @moduledoc """
  Components for real-time collaboration features in the Flow Editor.

  Includes:
  - Online users display (avatars with colored rings)
  - Collaboration toasts for remote change notifications
  """
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders the online users indicator showing avatars of users currently in the flow.

  ## Examples

      <.online_users users={@online_users} current_user_id={@current_scope.user.id} />
  """
  attr :users, :list, required: true, doc: "List of online user presence maps"

  attr :current_user_id, :integer,
    required: true,
    doc: "Current user's ID to exclude from display"

  def online_users(assigns) do
    other_users = Enum.reject(assigns.users, &(&1.user_id == assigns.current_user_id))
    assigns = assign(assigns, :other_users, other_users)

    ~H"""
    <div :if={@other_users != []} class="flex items-center gap-1">
      <div class="flex -space-x-2">
        <div
          :for={user <- Enum.take(@other_users, 5)}
          class="avatar placeholder tooltip tooltip-bottom"
          data-tip={user.display_name || user.email}
        >
          <div
            class="size-8 rounded-full ring-2 bg-base-300 text-base-content"
            style={"ring-color: #{user.color};"}
          >
            <span class="text-xs">{get_initials(user)}</span>
          </div>
        </div>
        <div
          :if={length(@other_users) > 5}
          class="avatar placeholder tooltip tooltip-bottom"
          data-tip={
            ngettext(
              "%{count} more user",
              "%{count} more users",
              length(@other_users) - 5,
              count: length(@other_users) - 5
            )
          }
        >
          <div class="size-8 rounded-full bg-base-300 text-base-content text-xs ring-2 ring-base-content/20">
            +{length(@other_users) - 5}
          </div>
        </div>
      </div>
      <span class="text-xs text-base-content/60 ml-1">
        {ngettext("%{count} collaborator", "%{count} collaborators", length(@other_users),
          count: length(@other_users)
        )}
      </span>
    </div>
    """
  end

  defp get_initials(%{display_name: name}) when is_binary(name) and name != "" do
    name
    |> String.split(~r/\s+/)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp get_initials(%{email: email}) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp get_initials(_), do: "?"

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
            <span class="text-base-content/70">{@message}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp action_message(:node_added, _), do: gettext("added a node")
  defp action_message(:node_deleted, _), do: gettext("deleted a node")
  defp action_message(:node_updated, _), do: gettext("updated a node")
  defp action_message(:node_moved, _), do: gettext("moved a node")
  defp action_message(:connection_added, _), do: gettext("added a connection")
  defp action_message(:connection_deleted, _), do: gettext("deleted a connection")
  defp action_message(:connection_updated, _), do: gettext("updated a connection")
  defp action_message(:user_joined, _), do: gettext("joined the flow")
  defp action_message(:user_left, _), do: gettext("left the flow")
  defp action_message(_, _), do: gettext("made a change")

  @spec get_email_name(any()) :: String.t()
  defp get_email_name(email) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp get_email_name(_), do: "Someone"

  @doc """
  Renders a lock indicator on a node.

  ## Examples

      <.node_lock_indicator lock={@node_lock} />
  """
  attr :lock, :map, default: nil, doc: "Lock info map with user_email and user_color"

  def node_lock_indicator(assigns) do
    ~H"""
    <div
      :if={@lock}
      class="absolute -top-2 -right-2 flex items-center gap-1 px-1.5 py-0.5 rounded-full text-xs bg-base-100 shadow-sm border border-base-300"
      style={"border-color: #{@lock.user_color};"}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        class="size-3"
        style={"color: #{@lock.user_color};"}
      >
        <path
          fill-rule="evenodd"
          d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z"
          clip-rule="evenodd"
        />
      </svg>
      <span class="font-medium" style={"color: #{@lock.user_color};"}>
        {get_email_name(@lock.user_email)}
      </span>
    </div>
    """
  end
end
