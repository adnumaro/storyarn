defmodule StoryarnWeb.Live.Hooks.RequireFeatureFlag do
  @moduledoc """
  Halts a LiveView mount if the current user does not have `flag` enabled.

  Usage:

      on_mount {StoryarnWeb.Live.Hooks.RequireFeatureFlag, :ai_integrations}

  Users without the flag are redirected to their settings home with a flash.
  The sidebar will already hide the entry — this hook is defense-in-depth
  against direct URL access.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Storyarn.FeatureFlags

  def on_mount(flag, _params, _session, socket) when is_atom(flag) do
    user = socket.assigns.current_scope.user

    if FeatureFlags.enabled?(flag, for: user) do
      {:cont, assign(socket, :feature_flag, flag)}
    else
      socket =
        socket
        |> put_flash(
          :error,
          dgettext("integrations", "This feature is not available for your account.")
        )
        |> redirect(to: ~p"/users/settings")

      {:halt, socket}
    end
  end
end
