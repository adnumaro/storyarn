defmodule StoryarnWeb.UserLive.Login do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <.vue
        v-component="auth/Login"
        v-socket={@socket}
        id="login-vue"
        email={@form.params["email"] || ""}
        readonly={!!@current_scope}
        local-mail-adapter={local_mail_adapter?()}
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

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case RateLimiter.check_magic_link(email) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )
        end

        info =
          dgettext(
            "identity",
            "If your email is in our system, you will receive instructions for logging in shortly."
          )

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("identity", "Too many requests. Please try again later."))
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:storyarn, Storyarn.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
