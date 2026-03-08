defmodule StoryarnWeb.ProjectLive.Components.SettingsComponents do
  @moduledoc """
  Private helper functions extracted from `StoryarnWeb.ProjectLive.Settings`.

  Contains form changesets, provider helpers, and do_* action helpers
  used by the settings LiveView.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Accounts
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Projects

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

  @project_invite_roles ~w(editor viewer)

  def do_send_invitation(socket, invite_params) do
    role = invite_params["role"]

    if role in @project_invite_roles do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user

      request_info = %{
        invitee_email: String.downcase(invite_params["email"]),
        requester_email: user.email,
        type: "project",
        entity_name: project.name,
        entity_id: project.id,
        role: role,
        locale: Gettext.get_locale(StoryarnWeb.Gettext)
      }

      Accounts.notify_admin_invitation_request(request_info)

      socket =
        socket
        |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
        |> put_flash(
          :info,
          dgettext("projects", "Invitation request sent. An admin will review it shortly.")
        )

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Invalid role."))}
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
