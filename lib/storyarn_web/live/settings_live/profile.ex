defmodule StoryarnWeb.SettingsLive.Profile do
  @moduledoc """
  LiveView for user profile and email settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.Components.SettingsLayout

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, dgettext("settings", "Email changed successfully."))

        {:error, :transaction_aborted} ->
          put_flash(
            socket,
            :error,
            dgettext("settings", "Email change link is invalid or it has expired.")
          )
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    profile_changeset = Accounts.change_user_profile(user, %{})

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Profile Settings"))
      |> assign(:current_path, ~p"/users/settings")
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:profile_form, to_form(profile_changeset))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/account/settings/Profile"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-profile-vue"
        profile-form={@profile_form}
        email-form={@email_form}
        current-email={@current_email}
      />
    </SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("validate_profile", %{"user" => user_params}, socket) do
    profile_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        path =
          if updated_user.locale do
            ~p"/users/settings?locale=#{updated_user.locale}"
          else
            ~p"/users/settings"
          end

        {:noreply,
         socket
         |> put_flash(:info, dgettext("settings", "Profile updated successfully."))
         |> redirect(to: path)}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info =
          dgettext(
            "settings",
            "A link to confirm your email change has been sent to the new address."
          )

        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end
end
