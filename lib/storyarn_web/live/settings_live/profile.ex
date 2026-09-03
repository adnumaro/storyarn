defmodule StoryarnWeb.SettingsLive.Profile do
  @moduledoc """
  Personal › Profile: display name and email.

  Sensitive sections lock in place when the sudo window has lapsed; the page
  re-authenticates through `StoryarnWeb.Live.Shared.SudoReauth`.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts
  alias StoryarnWeb.Helpers.SaveStatusTimer
  alias StoryarnWeb.Live.Shared.SudoReauth
  alias StoryarnWeb.UserAuth

  on_mount {UserAuth, :load_sudo_state}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if socket.assigns.sudo_active do
      confirm_email_change(socket, token)
    else
      {:ok,
       push_navigate(socket,
         to: UserAuth.sudo_confirmation_path(~p"/users/settings/confirm-email/#{token}"),
         replace: true
       )}
    end
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:page_title, dgettext("settings", "Profile Settings"))
      |> assign(:current_path, ~p"/users/settings")
      |> assign(:profile_form, to_form(Accounts.change_user_profile(user, %{})))
      |> assign(:email, user.email)
      |> assign(:save_status, :idle)
      |> SudoReauth.assign_reauth(~p"/users/settings")

    {:ok, socket}
  end

  defp confirm_email_change(socket, token) do
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

    return_to = UserAuth.with_sudo_grant(~p"/users/settings", socket.assigns.sudo_grant)
    {:ok, push_navigate(socket, to: return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
      sudo_grant={@sudo_grant}
    >
      <.vue
        v-component="live/account/settings/AccountSettingsProfile"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-profile-vue"
        profile-form={@profile_form}
        email={@email}
        save-status={Atom.to_string(@save_status)}
        sudo-active={@sudo_active}
        reauth={SudoReauth.reauth_props(@sudo_return_to, @sudo_handoff, @trigger_sudo_submit)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
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
    SudoReauth.with_sudo(socket, fn socket ->
      update_profile(socket, socket.assigns.current_scope.user, user_params)
    end)
  end

  def handle_event("request_email_change", %{"email" => email}, socket) do
    SudoReauth.with_sudo(socket, fn socket ->
      request_email_change(socket, socket.assigns.current_scope.user, email)
    end)
  end

  def handle_event("confirm_access", params, socket) do
    SudoReauth.confirm(socket, params)
  end

  @impl true
  def handle_info({:reset_save_status, token}, socket) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply, assign(socket, :save_status, :idle)}
    else
      {:noreply, socket}
    end
  end

  defp update_profile(socket, user, user_params) do
    case Accounts.update_user_profile(user, user_params) do
      {:ok, updated_user} ->
        # `authenticated_at` is virtual and is therefore lost when Ecto returns
        # the updated row. Preserve the current session's sudo timestamp so a
        # second save in the same LiveView does not spuriously require another
        # password confirmation.
        updated_user = %{updated_user | authenticated_at: user.authenticated_at}

        socket =
          socket
          |> assign(:current_scope, Accounts.scope_for_user(updated_user))
          |> assign(:profile_form, to_form(Accounts.change_user_profile(updated_user, %{})))
          |> SaveStatusTimer.mark_saved()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :insert))}
    end
  end

  defp request_email_change(socket, user, email) do
    changeset = Accounts.change_user_email(user, %{"email" => email})

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:reply, %{ok: true},
         put_flash(
           socket,
           :info,
           dgettext(
             "settings",
             "A link to confirm your email change has been sent to the new address."
           )
         )}

      {:error, changeset} ->
        {:reply, %{ok: false, error: first_email_error(changeset)}, socket}
    end
  end

  defp first_email_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.get(:email, [])
    |> List.first()
    |> Kernel.||(dgettext("settings", "Enter a valid email address."))
  end
end
