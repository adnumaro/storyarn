defmodule StoryarnWeb.UserLive.ForgotPassword do
  @moduledoc false

  use StoryarnWeb, :live_view

  import Ecto.Changeset, only: [cast: 3, validate_length: 3, validate_required: 2]

  alias Storyarn.Accounts
  alias Storyarn.RateLimiter
  alias Storyarn.Shared.Validations
  alias StoryarnWeb.ClientIp
  alias StoryarnWeb.PublicURLs

  require Logger

  on_mount {StoryarnWeb.UserAuth, :redirect_if_user_is_authenticated}

  @request_types %{email: :string}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.AuthLayout.auth
      flash={@flash}
      current_scope={@current_scope}
      socket={@socket}
      seo_metadata={@seo_metadata}
    >
      <.vue
        v-component="live/auth/reset-password/AuthForgotPasswordForm"
        v-socket={@socket}
        v-inject="auth-layout"
        id="forgot-password-vue"
        form={@form}
        login-url={PublicURLs.locale_handoff_path(~p"/users/log-in", @locale)}
        instructions-sent={@instructions_sent}
        request-error={@request_error}
      />
    </StoryarnWeb.Components.AuthLayout.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:client_ip, ClientIp.from_socket(socket))
     |> assign(:instructions_sent, false)
     |> assign(:request_error, nil)
     |> assign_form(request_changeset(%{}))}
  end

  @impl true
  def handle_event("validate", %{"password_reset" => params}, socket) do
    changeset =
      params
      |> request_changeset()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:request_error, nil)
     |> assign_form(changeset)}
  end

  def handle_event("send_instructions", %{"password_reset" => params}, socket) do
    changeset = request_changeset(params)

    if changeset.valid? do
      send_reset_instructions(socket, Ecto.Changeset.get_field(changeset, :email))
    else
      {:noreply,
       socket
       |> assign(:request_error, nil)
       |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("reset_request_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:instructions_sent, false)
     |> assign(:request_error, nil)
     |> assign_form(request_changeset(%{}))}
  end

  defp send_reset_instructions(socket, email) do
    case RateLimiter.check_password_reset(socket.assigns.client_ip, email) do
      :ok ->
        reset_url = fn token ->
          reset_path = ~p"/users/reset-password/#{token}"

          reset_path
          |> PublicURLs.locale_handoff_path(socket.assigns.locale)
          |> then(&Phoenix.VerifiedRoutes.unverified_url(socket, &1))
        end

        case Accounts.request_user_reset_password_instructions(email, reset_url) do
          {:ok, _email} ->
            :ok

          {:error, reason} ->
            Logger.warning("Password reset instructions could not be queued reason=#{inspect(reason)}")
        end

        {:noreply,
         socket
         |> assign(:instructions_sent, true)
         |> assign(:request_error, nil)
         |> assign_form(request_changeset(%{"email" => email}))}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(:instructions_sent, false)
         |> assign(:request_error, dgettext("identity", "Too many password reset requests. Please try again later."))
         |> assign_form(request_changeset(%{"email" => email}))}
    end
  end

  defp request_changeset(attrs) do
    {%{}, @request_types}
    |> cast(attrs || %{}, [:email])
    |> validate_required([:email])
    |> Validations.validate_email_format()
    |> validate_length(:email, max: 160)
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "password_reset"))
  end
end
