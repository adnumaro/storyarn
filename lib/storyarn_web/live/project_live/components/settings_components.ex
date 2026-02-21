defmodule StoryarnWeb.ProjectLive.Components.SettingsComponents do
  @moduledoc """
  Private helper functions extracted from `StoryarnWeb.ProjectLive.Settings`.

  Contains form changesets, provider helpers, and do_* action helpers
  used by the settings LiveView.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Flows
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Projects
  alias Storyarn.Repo

  # ---------------------------------------------------------------------------
  # Form changesets
  # ---------------------------------------------------------------------------

  def invite_changeset(params) do
    types = %{email: :string, role: :string}
    defaults = %{email: "", role: "editor"}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :role])
  end

  def get_provider_config(project_id) do
    Repo.get_by(ProviderConfig, project_id: project_id, provider: "deepl")
  end

  def provider_changeset(nil) do
    ProviderConfig.changeset(%ProviderConfig{api_endpoint: "https://api-free.deepl.com"}, %{})
  end

  def provider_changeset(%ProviderConfig{} = config) do
    ProviderConfig.changeset(config, %{})
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_number(n), do: to_string(n)

  def repair_message(0), do: dgettext("projects", "All variable references are up to date.")

  def repair_message(count) do
    dngettext(
      "projects",
      "Repaired %{count} node.",
      "Repaired %{count} nodes.",
      count,
      count: count
    )
  end

  # ---------------------------------------------------------------------------
  # Action helpers (called from handle_event)
  # ---------------------------------------------------------------------------

  def do_test_provider_connection(socket) do
    config = get_provider_config(socket.assigns.project.id)

    if config && config.api_key_encrypted do
      case Storyarn.Localization.Providers.DeepL.get_usage(config) do
        {:ok, usage} ->
          {:noreply,
           socket
           |> assign(:provider_usage, usage)
           |> put_flash(:info, dgettext("projects", "Connection successful."))}

        {:error, :invalid_api_key} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Invalid API key."))}

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Connection failed. Check your API key and endpoint.")
           )}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "No API key configured."))}
    end
  end

  def do_save_provider_config(socket, params) do
    project = socket.assigns.project
    existing = get_provider_config(project.id)

    # Don't overwrite API key if the field is empty (user didn't change it)
    params =
      if params["api_key_encrypted"] == "" do
        Map.delete(params, "api_key_encrypted")
      else
        params
      end

    result =
      case existing do
        nil ->
          %ProviderConfig{project_id: project.id}
          |> ProviderConfig.changeset(Map.put(params, "provider", "deepl"))
          |> Repo.insert()

        config ->
          config
          |> ProviderConfig.changeset(params)
          |> Repo.update()
      end

    case result do
      {:ok, config} ->
        socket =
          socket
          |> assign(:provider_form, to_form(provider_changeset(config), as: "provider"))
          |> assign(:has_api_key, config.api_key_encrypted != nil)
          |> put_flash(:info, dgettext("projects", "Provider settings saved."))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :provider_form,
           to_form(changeset |> Map.put(:action, :validate), as: "provider")
         )}
    end
  end

  def do_repair_variable_references(socket) do
    case Flows.repair_stale_references(socket.assigns.project.id) do
      {:ok, count} ->
        {:noreply, put_flash(socket, :info, repair_message(count))}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Failed to repair variable references.")
         )}
    end
  end

  def do_send_invitation(socket, invite_params) do
    case Projects.create_invitation(
           socket.assigns.project,
           socket.assigns.current_scope.user,
           invite_params["email"],
           invite_params["role"]
         ) do
      {:ok, _invitation} ->
        pending_invitations = Projects.list_pending_invitations(socket.assigns.project.id)

        socket =
          socket
          |> assign(:pending_invitations, pending_invitations)
          |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
          |> put_flash(:info, dgettext("projects", "Invitation sent successfully."))

        {:noreply, socket}

      {:error, :already_member} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "This email is already a member of the project.")
         )}

      {:error, :already_invited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "An invitation has already been sent to this email.")
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Too many invitations. Please try again later.")
         )}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Failed to send invitation. Please try again.")
         )}
    end
  end

  def do_revoke_invitation(socket, id) do
    invitation = Enum.find(socket.assigns.pending_invitations, &(to_string(&1.id) == id))

    if invitation do
      {:ok, _} = Projects.revoke_invitation(invitation)
      pending_invitations = Projects.list_pending_invitations(socket.assigns.project.id)

      socket =
        socket
        |> assign(:pending_invitations, pending_invitations)
        |> put_flash(:info, dgettext("projects", "Invitation revoked."))

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Invitation not found."))}
    end
  end

  def do_remove_member(socket, id) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == id))

    if member && member.role != "owner" do
      case Projects.remove_member(member) do
        {:ok, _} ->
          members = Projects.list_project_members(socket.assigns.project.id)

          socket =
            socket
            |> assign(:members, members)
            |> put_flash(:info, dgettext("projects", "Member removed."))

          {:noreply, socket}

        {:error, :cannot_remove_owner} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Cannot remove the project owner.")
           )}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Member not found."))}
    end
  end
end
