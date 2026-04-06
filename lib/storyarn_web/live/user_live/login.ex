defmodule StoryarnWeb.UserLive.Login do
  @moduledoc false

  use StoryarnWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <.vue
        v-component="modules/auth/SignIn"
        v-socket={@socket}
        id="login-vue"
        email={@form.params["email"] || ""}
        readonly={!!@current_scope}
        local-mail-adapter={local_mail_adapter?()}
        csrf-token={Plug.CSRFProtection.get_csrf_token()}
        login-action={~p"/users/log-in"}
      />
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form)}
  end

  # Magic links have been replaced by Email + Password authentication

  defp local_mail_adapter? do
    Application.get_env(:storyarn, Storyarn.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
