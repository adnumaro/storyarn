defmodule StoryarnWeb.SettingsLive.Profile do
  @moduledoc """
  LiveView for user profile and email settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Accounts

  on_mount {StoryarnWeb.UserAuth, :require_sudo_mode}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, dgettext("settings", "Email changed successfully."))

        {:error, :transaction_aborted} ->
          put_flash(socket, :error, dgettext("settings", "Email change link is invalid or it has expired."))
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
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_path={@current_path}
    >
      <:title>{dgettext("settings", "Profile")}</:title>
      <:subtitle>{dgettext("settings", "Manage your personal information and email address")}</:subtitle>

      <div class="space-y-8">
        <%!-- Profile Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("settings", "Personal Information")}</h3>
          <.form
            for={@profile_form}
            id="profile_form"
            phx-submit="update_profile"
            phx-change="validate_profile"
            class="space-y-4"
          >
            <.input
              field={@profile_form[:display_name]}
              type="text"
              label={dgettext("settings", "Display Name")}
              placeholder={dgettext("settings", "How you want to be called")}
            />
            <div class="flex justify-end">
              <.button variant="primary" phx-disable-with={dgettext("settings", "Saving...")}>
                {dgettext("settings", "Save Profile")}
              </.button>
            </div>
          </.form>
        </section>

        <div class="divider" />

        <%!-- Email Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("settings", "Email Address")}</h3>
          <p class="text-sm text-base-content/70 mb-4">
            {dgettext("settings", "Your email is used for login and notifications.")}
          </p>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="space-y-4"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label={dgettext("settings", "Email")}
              autocomplete="username"
              required
            />
            <div class="flex justify-end">
              <.button variant="primary" phx-disable-with={dgettext("settings", "Changing...")}>
                {dgettext("settings", "Change Email")}
              </.button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.settings>
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
      {:ok, _user} ->
        {:noreply, put_flash(socket, :info, dgettext("settings", "Profile updated successfully."))}

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

        info = dgettext("settings", "A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end
end
