defmodule StoryarnWeb.ProjectLive.Components.SettingsComponents do
  @moduledoc """
  Shared helper functions for `StoryarnWeb.ProjectSettingsLive.*` LiveViews.

  Contains form changesets, provider helpers, and do_* action helpers
  used by the settings LiveView.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Shared.Validations
  alias Storyarn.Versioning
  alias Storyarn.Workers.RestoreProjectWorker

  require Logger

  # ---------------------------------------------------------------------------
  # Form changesets
  # ---------------------------------------------------------------------------

  @project_invite_roles ~w(editor viewer)

  def invite_changeset(params) do
    types = %{email: :string, role: :string}
    defaults = %{email: "", role: "editor"}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.update_change(:email, &String.trim/1)
    |> Ecto.Changeset.validate_required([:email, :role])
    |> Validations.validate_email_format()
    |> Ecto.Changeset.validate_inclusion(:role, @project_invite_roles)
  end

  def get_provider_config(project_id) do
    Localization.get_provider_config(project_id)
  end

  def provider_changeset(config) do
    Localization.change_provider_config(config)
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
      case Localization.get_deepl_usage(config) do
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

    # Don't overwrite API key if the field is empty (user didn't change it)
    params =
      if params["api_key_encrypted"] == "" do
        Map.delete(params, "api_key_encrypted")
      else
        params
      end

    result = Localization.upsert_provider_config(project, params)

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
           changeset |> Map.put(:action, :validate) |> to_form(as: "provider")
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

  def snapshot_changeset(params) do
    types = %{title: :string, description: :string}
    defaults = %{title: "", description: ""}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_length(:title, max: 255)
    |> Ecto.Changeset.validate_length(:description, max: 500)
  end

  def format_snapshot_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  def format_snapshot_size(bytes) when is_integer(bytes) and bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"

  def format_snapshot_size(bytes) when is_integer(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_snapshot_size(_), do: "—"

  def do_create_snapshot(socket, params) do
    project = socket.assigns.project
    user_id = socket.assigns.current_scope.user.id

    case Billing.can_create_project_snapshot?(project.id, project.workspace_id) do
      :ok ->
        opts =
          Enum.reject([title: params["title"], description: params["description"]], fn {_k, v} -> v == "" or is_nil(v) end)

        case Versioning.create_project_snapshot(project.id, user_id, opts) do
          {:ok, _snapshot} ->
            {:noreply,
             socket
             |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
             |> assign(:snapshot_form, to_form(snapshot_changeset(%{}), as: "snapshot"))
             |> assign(
               :can_create_snapshot,
               Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
             )
             |> put_flash(:info, dgettext("projects", "Project snapshot created."))}

          {:error, reason} ->
            Logger.error("Project snapshot creation failed: #{inspect(reason)}")

            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("projects", "Failed to create snapshot. Please try again.")
             )}
        end

      {:error, :limit_reached, _info} ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Snapshot limit reached for your plan."))}
    end
  end

  def do_restore_snapshot(socket, snapshot_id) do
    case Versioning.ensure_restore_enabled(:project_snapshot_restore) do
      :ok ->
        do_enabled_restore_snapshot(socket, snapshot_id)

      {:error, :restore_temporarily_disabled} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Project restoration failed. Please try again.")
         )}
    end
  end

  defp do_enabled_restore_snapshot(socket, snapshot_id) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user

    case Versioning.get_project_snapshot(project.id, snapshot_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Snapshot not found."))}

      _snapshot ->
        acquire_and_enqueue_restore(socket, project, user, snapshot_id)
    end
  end

  defp acquire_and_enqueue_restore(socket, project, user, snapshot_id) do
    case Projects.acquire_restoration_lock(project.id, user.id) do
      {:ok, _project} ->
        enqueue_locked_restore(socket, project, user, snapshot_id)

      {:error, :already_locked} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "A restoration is already in progress.")
         )}
    end
  end

  defp enqueue_locked_restore(socket, project, user, snapshot_id) do
    case enqueue_project_restore(project.id, snapshot_id, user.id) do
      {:ok, _job} ->
        Collaboration.broadcast_restoration_started(project.id, %{
          user_email: user.email
        })

        {:noreply,
         socket
         |> assign(:restoration_in_progress, true)
         |> put_flash(
           :info,
           dgettext(
             "projects",
             "Restoration started. All editors will be notified when complete."
           )
         )}

      {:error, _reason} ->
        Projects.release_restoration_lock(project.id)

        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Project restoration failed. Please try again.")
         )}
    end
  end

  defp enqueue_project_restore(project_id, snapshot_id, user_id) do
    %{project_id: project_id, snapshot_id: snapshot_id, user_id: user_id}
    |> RestoreProjectWorker.new()
    |> Oban.insert()
  end

  def do_delete_snapshot(socket, snapshot_id) do
    project = socket.assigns.project

    case Versioning.get_project_snapshot(project.id, snapshot_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Snapshot not found."))}

      snapshot ->
        case Versioning.delete_project_snapshot(snapshot) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
             |> assign(
               :can_create_snapshot,
               Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
             )
             |> put_flash(:info, dgettext("projects", "Snapshot deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete snapshot."))}
        end
    end
  end

  def do_send_invitation(socket, invite_params) do
    changeset = invite_changeset(invite_params)

    if changeset.valid? do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      email = Ecto.Changeset.get_field(changeset, :email)
      role = Ecto.Changeset.get_field(changeset, :role)

      project
      |> Projects.create_invitation(user, email, role)
      |> handle_project_invitation_result(socket)
    else
      {:noreply,
       socket
       |> assign(:invite_form, to_form(%{changeset | action: :validate}, as: "invite"))
       |> put_flash(
         :error,
         dgettext("projects", "Enter a valid email address and role.")
       )}
    end
  end

  defp handle_project_invitation_result({:ok, _invitation}, socket) do
    pending_invitations = Projects.list_pending_invitations(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
     |> assign(:pending_invitations, pending_invitations)
     |> push_event("invitation_sent", %{})
     |> put_flash(:info, dgettext("projects", "Invitation queued for delivery."))}
  end

  defp handle_project_invitation_result({:error, :already_member}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("projects", "This person is already a member of this project.")
     )}
  end

  defp handle_project_invitation_result({:error, :already_invited}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("projects", "An invitation has already been sent to this email.")
     )}
  end

  defp handle_project_invitation_result({:error, :rate_limited}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("projects", "Too many invitations have been sent. Try again later.")
     )}
  end

  defp handle_project_invitation_result({:error, :limit_reached, %{resource: :members_per_workspace}}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("projects", "Member limit reached for your plan."))}
  end

  defp handle_project_invitation_result({:error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("projects", "Could not send invitation."))}
  end

  def do_revoke_invitation(socket, id) do
    project_id = socket.assigns.project.id

    with {invitation_id, ""} <- Integer.parse(to_string(id)),
         %{project_id: ^project_id} = invitation <- Projects.get_pending_invitation(invitation_id),
         {:ok, _invitation} <- Projects.revoke_invitation(invitation) do
      pending_invitations = Projects.list_pending_invitations(project_id)

      {:noreply,
       socket
       |> assign(:pending_invitations, pending_invitations)
       |> put_flash(:info, dgettext("projects", "Invitation revoked."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Invitation not found."))}
    end
  end

  @doc """
  Navigation sections for the project settings sidebar.
  Shared between ProjectSettingsLive.* and ExportImportLive.Index.
  """
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
