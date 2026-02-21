defmodule StoryarnWeb.UserLive.Registration do
  @moduledoc false

  use StoryarnWeb, :live_view

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
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)
    ip_address = get_client_ip(socket)

    {:ok, socket |> assign(:ip_address, ip_address) |> assign_form(changeset),
     temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case RateLimiter.check_registration(socket.assigns.ip_address) do
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

  defp get_client_ip(socket) do
    # Check for X-Forwarded-For header first (common with reverse proxies)
    x_headers = get_connect_info(socket, :x_headers) || []

    case List.keyfind(x_headers, "x-forwarded-for", 0) do
      {"x-forwarded-for", forwarded} ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      nil ->
        # Fall back to peer_data
        case get_connect_info(socket, :peer_data) do
          %{address: ip} when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
          _ -> "unknown"
        end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
