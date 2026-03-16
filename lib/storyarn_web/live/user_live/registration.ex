defmodule StoryarnWeb.UserLive.Registration do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.UIComponents, only: [oauth_buttons: 1]

  alias Storyarn.Accounts
  alias Storyarn.Accounts.User
  alias Storyarn.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            {dgettext("identity", "Register for an account")}
            <:subtitle>
              {dgettext("identity", "Already registered?")}
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                {dgettext("identity", "Log in")}
              </.link>
              {dgettext("identity", "to your account now.")}
            </:subtitle>
          </.header>
        </div>

        <.oauth_buttons class="mb-4" />

        <div class="divider">{dgettext("identity", "or register with email")}</div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label={dgettext("identity", "Email")}
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />

          <.button
            phx-disable-with={dgettext("identity", "Creating account...")}
            class="btn btn-primary w-full"
          >
            {dgettext("identity", "Create an account")}
          </.button>
        </.form>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: StoryarnWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    # Registration disabled during invite-only beta
    # Extract client IP for rate limiting (only available during mount)
    ip =
      case get_connect_info(socket, :peer_data) do
        %{address: addr} when is_tuple(addr) -> addr |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end

    {:ok, socket |> assign(:client_ip, ip) |> redirect(to: ~p"/")}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case RateLimiter.check_registration(socket.assigns[:client_ip] || "unknown") do
      :ok ->
        do_register(socket, user_params)

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("identity", "Too many registration attempts. Please try again later.")
         )
         |> push_navigate(to: ~p"/users/register")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # Private helpers

  defp do_register(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext(
             "identity",
             "An email was sent to %{email}, please access it to confirm your account.",
             email: user.email
           )
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
