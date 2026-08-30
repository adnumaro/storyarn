defmodule StoryarnWeb.ProjectLive.Components.SettingsComponents do
  @moduledoc """
  Shared helper functions for `StoryarnWeb.ProjectSettingsLive.*` LiveViews.

  Contains form changesets, provider helpers, and do_* action helpers
  used by the settings LiveView.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Projects

  @max_pg_bigint 9_223_372_036_854_775_807

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
    |> Projects.validate_project_email_format()
    |> Ecto.Changeset.validate_inclusion(:role, @project_invite_roles)
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

  @doc false
  def serialize_storage_usage(storage, limit) do
    %{
      currentAssetsBytes: serialize_byte_count(storage.current_assets.bytes),
      assetTrashBytes: serialize_byte_count(storage.asset_trash.bytes),
      fullSnapshotsBytes: serialize_byte_count(storage.full_snapshots.bytes),
      activeReservationsBytes: serialize_byte_count(storage.active_reservations.bytes),
      totalAccountedBytes: serialize_byte_count(storage.accounted_bytes),
      limitBytes: serialized_storage_limit(limit),
      remainingBytes: remaining_storage_bytes(storage.accounted_bytes, limit),
      limitKind: storage_limit_kind(limit)
    }
  end

  @doc false
  def serialize_storage_bucket(bucket) do
    %{
      used: serialize_byte_count(bucket.used),
      limit: serialized_storage_limit(bucket.limit)
    }
  end

  @doc false
  def serialize_byte_count(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)

  defp remaining_storage_bytes(used, limit) when is_integer(limit) and limit >= 0 do
    serialize_byte_count(max(limit - used, 0))
  end

  defp remaining_storage_bytes(_used, _limit), do: nil

  defp serialized_storage_limit(limit) when is_integer(limit) and limit >= 0 do
    serialize_byte_count(limit)
  end

  defp serialized_storage_limit(_limit), do: nil

  defp storage_limit_kind(limit) when is_integer(limit) and limit >= 0, do: "limited"
  defp storage_limit_kind(limit) when limit in [:unlimited, :infinity], do: "unlimited"
  defp storage_limit_kind(_limit), do: "unknown"

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

  def partial_repair_message(repaired_count, failed_count) do
    repaired =
      dngettext(
        "projects",
        "%{count} node repaired",
        "%{count} nodes repaired",
        repaired_count,
        count: repaired_count
      )

    failed =
      dngettext(
        "projects",
        "%{count} node failed",
        "%{count} nodes failed",
        failed_count,
        count: failed_count
      )

    dgettext(
      "projects",
      "Repair partially completed: %{repaired}; %{failed}.",
      repaired: repaired,
      failed: failed
    )
  end

  def failed_repair_message(failed_count) do
    dngettext(
      "projects",
      "No nodes could be repaired; %{count} node failed. Try again.",
      "No nodes could be repaired; %{count} nodes failed. Try again.",
      failed_count,
      count: failed_count
    )
  end

  # ---------------------------------------------------------------------------
  # Action helpers (called from handle_event)
  # ---------------------------------------------------------------------------

  def do_repair_variable_references(socket) do
    do_repair_variable_references(socket, &Projects.repair_stale_project_variable_references/2)
  end

  @doc false
  def do_repair_variable_references(socket, repair_fun) when is_function(repair_fun, 2) do
    case repair_fun.(socket.assigns.current_scope, socket.assigns.project.id) do
      {:ok, count} ->
        {:noreply, put_flash(socket, :info, repair_message(count))}

      {:error, {:partial_variable_reference_repair, %{repaired_count: repaired_count, failures: failures}}}
      when repaired_count > 0 and is_list(failures) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           partial_repair_message(repaired_count, length(failures))
         )}

      {:error, {:partial_variable_reference_repair, %{repaired_count: 0, failures: failures}}}
      when is_list(failures) and failures != [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           failed_repair_message(length(failures))
         )}

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
    changeset = invite_changeset(invite_params)

    if changeset.valid? do
      project = socket.assigns.project
      email = Ecto.Changeset.get_field(changeset, :email)
      role = Ecto.Changeset.get_field(changeset, :role)

      socket.assigns.current_scope
      |> Projects.create_invitation(project.id, email, role)
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

  defp handle_project_invitation_result({:error, :unauthorized}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("projects", "Only the current project owner can invite members.")
     )}
  end

  defp handle_project_invitation_result({:error, :ownership_invariant_violation}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("projects", "The invitation could not be sent because project ownership is inconsistent.")
     )}
  end

  defp handle_project_invitation_result({:error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("projects", "Could not send invitation."))}
  end

  def do_revoke_invitation(socket, id) do
    project_id = socket.assigns.project.id

    with {:ok, invitation_id} <- parse_positive_pg_bigint(id),
         {:ok, _invitation} <-
           Projects.revoke_invitation(
             socket.assigns.current_scope,
             project_id,
             invitation_id
           ) do
      pending_invitations = Projects.list_pending_invitations(project_id)

      {:noreply,
       socket
       |> assign(:pending_invitations, pending_invitations)
       |> put_flash(:info, dgettext("projects", "Invitation revoked."))}
    else
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "Only the current project owner can revoke invitations.")
         )}

      {:error, :ownership_invariant_violation} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "The invitation could not be revoked because project ownership is inconsistent.")
         )}

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Invitation not found."))}
    end
  end

  @doc """
  Navigation sections for the project settings sidebar.
  Shared between ProjectSettingsLive.* and ExportImportLive.Index.
  """
  def do_remove_member(socket, id) do
    case parse_positive_pg_bigint(id) do
      {:ok, membership_id} ->
        case Projects.remove_member(
               socket.assigns.current_scope,
               socket.assigns.project.id,
               membership_id
             ) do
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

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Member not found."))}

          {:error, :unauthorized} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("projects", "Only the current project owner can remove members.")
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to remove member."))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Member not found."))}
    end
  end

  defp parse_positive_pg_bigint(value) when is_integer(value) and value > 0 and value <= @max_pg_bigint, do: {:ok, value}

  defp parse_positive_pg_bigint(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= @max_pg_bigint -> {:ok, id}
      _invalid -> :error
    end
  end

  defp parse_positive_pg_bigint(_value), do: :error
end
