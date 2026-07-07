defmodule StoryarnWeb.UserLive.Login do
  @moduledoc false

  use StoryarnWeb, :live_view

  import Ecto.Changeset,
    only: [add_error: 3, cast: 3, get_field: 2, validate_length: 3, validate_required: 2]

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias Storyarn.Shared.Validations
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.UserLoginToken

  @login_types %{email: :string, password: :string}
  @login_fields Map.keys(@login_types)

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.AuthLayout.auth
      flash={@flash}
      current_scope={@current_scope}
      socket={@socket}
    >
      <.vue
        v-component="live/auth/login/AuthLoginForm"
        v-socket={@socket}
        v-inject="auth-layout"
        id="login-vue"
        form={@form}
        readonly={!!@current_scope}
        trigger-submit={@trigger_submit}
        login-token={@login_token}
        local-mail-adapter={local_mail_adapter?()}
        csrf-token={Plug.CSRFProtection.get_csrf_token()}
        login-action={~p"/users/log-in"}
        forgot-password-url={~p"/users/reset-password"}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    login_error = Phoenix.Flash.get(socket.assigns.flash, :login_error)

    changeset =
      if login_error do
        invalid_credentials_changeset(email, login_error)
      else
        initial_login_changeset(%{"email" => email})
      end

    {:ok,
     socket
     |> assign(:client_ip, ClientIp.from_socket(socket))
     |> assign(:trigger_submit, false)
     |> assign(:login_token, nil)
     |> assign_form(changeset)}
  end

  # Magic links have been replaced by Email + Password authentication

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      user_params
      |> login_changeset()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:trigger_submit, false)
     |> assign(:login_token, nil)
     |> assign_form(changeset)}
  end

  def handle_event("log_in", %{"user" => user_params}, socket) do
    changeset = login_changeset(user_params)

    if changeset.valid? do
      authenticate(socket, changeset, user_params)
    else
      {:noreply,
       socket
       |> assign(:trigger_submit, false)
       |> assign(:login_token, nil)
       |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  defp authenticate(socket, changeset, user_params) do
    case RateLimiter.check_login(socket.assigns.client_ip) do
      :ok ->
        email = get_field(changeset, :email) || ""
        password = get_field(changeset, :password) || ""

        case Accounts.get_user_by_email_and_password(email, password) do
          nil ->
            invalid_credentials(socket, email)

          user ->
            {:noreply,
             socket
             |> assign(:trigger_submit, true)
             |> assign(:login_token, UserLoginToken.sign_user(user))
             |> assign_form(initial_login_changeset(%{"email" => user_params["email"]}))}
        end

      {:error, :rate_limited} ->
        message = dgettext("identity", "Too many login attempts. Please try again later.")

        {:noreply,
         socket
         |> assign(:trigger_submit, false)
         |> assign(:login_token, nil)
         |> assign_form(invalid_credentials_changeset(user_params["email"], message))}
    end
  end

  defp invalid_credentials(socket, email) do
    {:noreply,
     socket
     |> assign(:trigger_submit, false)
     |> assign(:login_token, nil)
     |> assign_form(invalid_credentials_changeset(email, dgettext("identity", "Invalid email or password")))}
  end

  defp login_changeset(attrs) do
    attrs
    |> initial_login_changeset()
    |> validate_required([:email, :password])
    |> Validations.validate_email_format()
    |> validate_length(:email, max: 160)
  end

  defp initial_login_changeset(attrs) do
    cast({%{}, @login_types}, attrs || %{}, @login_fields)
  end

  defp invalid_credentials_changeset(email, message) do
    %{"email" => email}
    |> initial_login_changeset()
    |> validate_length(:email, max: 160)
    |> add_error(:password, message)
    |> Map.put(:action, :insert)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  defp local_mail_adapter? do
    Application.get_env(:storyarn, Storyarn.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
