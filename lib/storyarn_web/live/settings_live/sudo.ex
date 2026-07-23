defmodule StoryarnWeb.SettingsLive.Sudo do
  @moduledoc false

  alias StoryarnWeb.UserAuth

  def authorize(socket, return_to, fun) when is_function(fun, 1) do
    case UserAuth.authorize_sudo(
           socket.assigns.current_scope.user,
           socket.assigns.sudo_session_token,
           socket.assigns.sudo_grant
         ) do
      {:ok, _grant} ->
        fun.(socket)

      :error ->
        {:noreply,
         Phoenix.LiveView.push_navigate(socket,
           to: UserAuth.sudo_confirmation_path(return_to)
         )}
    end
  end
end
