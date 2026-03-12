defmodule StoryarnWeb.ProjectLive.Settings do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.MemberComponents
  import StoryarnWeb.Components.ColorPicker
  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
      back_label={dgettext("projects", "Back to project")}
      sidebar_sections={project_settings_sections(@workspace, @project)}
    >
      <:title>{section_title(@live_action)}</:title>
      <:subtitle>{section_subtitle(@live_action)}</:subtitle>

      <.section_content
        live_action={@live_action}
        project_form={@project_form}
        members={@members}
        current_scope={@current_scope}
        invite_form={@invite_form}
        theme_primary={@theme_primary}
        theme_accent={@theme_accent}
        has_custom_theme={@has_custom_theme}
        provider_form={@provider_form}
        has_api_key={@has_api_key}
        provider_usage={@provider_usage}
        snapshots={@snapshots}
        snapshot_form={@snapshot_form}
        can_create_snapshot={@can_create_snapshot}
        restoration_in_progress={@restoration_in_progress}
        version_control_form={@version_control_form}
        version_usage={@version_usage}
      />

      <.confirm_modal
        id="repair-refs-confirm"
        title={dgettext("projects", "Repair variable references?")}
        message={dgettext("projects", "This will update node data across the entire project.")}
        confirm_text={dgettext("projects", "Continue")}
        on_confirm={JS.push("repair_variable_references")}
      />

      <.confirm_modal
        id="delete-project-confirm"
        title={dgettext("projects", "Delete project?")}
        message={dgettext("projects", "This action cannot be undone.")}
        confirm_text={dgettext("projects", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("delete_project")}
      />
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Section content
  # ===========================================================================

  defp section_content(%{live_action: :general} = assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Project Details --%>
      <section>
        <.form
          for={@project_form}
          id="project-form"
          phx-submit="update_project"
          phx-change="validate_project"
        >
          <.input
            field={@project_form[:name]}
            type="text"
            label={dgettext("projects", "Project Name")}
            required
          />
          <.input
            field={@project_form[:description]}
            type="textarea"
            label={dgettext("projects", "Description")}
            rows={3}
          />
          <.form_actions>
            <.button variant="primary" phx-disable-with={dgettext("projects", "Saving...")}>
              {dgettext("projects", "Save Changes")}
            </.button>
          </.form_actions>
        </.form>
      </section>

      <div class="divider" />

      <%!-- Appearance --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("settings", "Appearance")}</h3>
        <div class="flex items-center gap-3">
          <.theme_toggle />
        </div>
      </section>

      <div class="divider" />

      <%!-- Theme --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Project Theme")}</h3>
        <div class="card bg-base-200 p-4">
          <div class="flex gap-8 items-start">
            <div>
              <label class="text-sm font-medium mb-2 block">
                {dgettext("projects", "Primary")}
              </label>
              <div class="flex items-center gap-3">
                <.color_picker
                  id="theme-primary"
                  color={@theme_primary}
                  event="update_theme_primary"
                />
                <code class="text-xs opacity-60">{@theme_primary}</code>
              </div>
            </div>
            <div>
              <label class="text-sm font-medium mb-2 block">
                {dgettext("projects", "Accent")}
              </label>
              <div class="flex items-center gap-3">
                <.color_picker
                  id="theme-accent"
                  color={@theme_accent}
                  event="update_theme_accent"
                />
                <code class="text-xs opacity-60">{@theme_accent}</code>
              </div>
            </div>
          </div>
          <.form_actions>
            <.button :if={@has_custom_theme} phx-click="reset_theme">
              {dgettext("projects", "Reset to Default")}
            </.button>
            <.button variant="primary" phx-click="save_theme">
              {dgettext("projects", "Apply Theme")}
            </.button>
          </.form_actions>
        </div>
      </section>

      <div class="divider" />

      <%!-- Maintenance --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Maintenance")}</h3>
        <div class="card bg-base-200 p-4">
          <p class="text-sm mb-3">
            {dgettext(
              "projects",
              "If you renamed sheet shortcuts or variable names, flow nodes may reference old names. Use this to repair them."
            )}
          </p>
          <.form_actions>
            <.button variant="primary" phx-click={show_modal("repair-refs-confirm")}>
              {dgettext("projects", "Repair variable references")}
            </.button>
          </.form_actions>
        </div>
      </section>

      <div class="divider" />

      <.danger_zone
        message={
          dgettext(
            "projects",
            "Once you delete a project, there is no going back. Please be certain."
          )
        }
        on_click={show_modal("delete-project-confirm")}
      >
        {dgettext("projects", "Delete Project")}
      </.danger_zone>
    </div>
    """
  end

  defp section_content(%{live_action: :localization} = assigns) do
    ~H"""
    <div>
      <div class="card bg-base-200 p-4">
        <h4 class="font-medium mb-3">{dgettext("projects", "Translation Provider (DeepL)")}</h4>

        <.form
          for={@provider_form}
          id="provider-config-form"
          phx-submit="save_provider_config"
        >
          <.input
            field={@provider_form[:api_key_encrypted]}
            type="password"
            label={dgettext("projects", "API Key")}
            placeholder={if @has_api_key, do: "••••••••", else: ""}
          />
          <.input
            field={@provider_form[:api_endpoint]}
            type="select"
            label={dgettext("projects", "API Tier")}
            options={[
              {dgettext("projects", "Free (api-free.deepl.com)"), "https://api-free.deepl.com"},
              {dgettext("projects", "Pro (api.deepl.com)"), "https://api.deepl.com"}
            ]}
          />
          <.form_actions>
            <.button
              :if={@has_api_key}
              type="button"
              phx-click="test_provider_connection"
              phx-disable-with={dgettext("projects", "Testing...")}
            >
              {dgettext("projects", "Test Connection")}
            </.button>
            <.button variant="primary" phx-disable-with={dgettext("projects", "Saving...")}>
              {dgettext("projects", "Save")}
            </.button>
          </.form_actions>
        </.form>

        <div :if={@provider_usage} class="mt-3 text-sm opacity-70">
          {dgettext("projects", "Usage: %{used} / %{limit} characters",
            used: format_number(@provider_usage.character_count),
            limit: format_number(@provider_usage.character_limit)
          )}
        </div>
      </div>
    </div>
    """
  end

  defp section_content(%{live_action: :members} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="space-y-3">
        <.member_row
          :for={member <- @members}
          member={member}
          current_user_id={@current_scope.user.id}
          can_manage={true}
          on_remove="remove_member"
        />
      </div>

      <div class="card bg-base-200 p-4">
        <h4 class="font-medium mb-3">{dgettext("projects", "Request member invitation")}</h4>
        <p class="text-sm opacity-70 mb-3">
          {dgettext("projects", "Invitation requests are reviewed by an admin before being sent.")}
        </p>
        <.form for={@invite_form} id="invite-form" phx-submit="send_invitation">
          <div class="flex gap-3 items-end">
            <div class="flex-1">
              <.input
                field={@invite_form[:email]}
                type="email"
                label={dgettext("projects", "Email address")}
                placeholder="colleague@example.com"
                required
              />
            </div>
            <div class="w-32">
              <.input
                field={@invite_form[:role]}
                type="select"
                label={dgettext("projects", "Role")}
                options={[
                  {dgettext("projects", "Editor"), "editor"},
                  {dgettext("projects", "Viewer"), "viewer"}
                ]}
              />
            </div>
          </div>
          <.form_actions>
            <.button variant="primary">
              {dgettext("projects", "Request Invitation")}
            </.button>
          </.form_actions>
        </.form>
      </div>
    </div>
    """
  end

  defp section_content(%{live_action: :snapshots} = assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Restoration In Progress Banner --%>
      <div :if={@restoration_in_progress} class="alert alert-warning">
        <.icon name="loader" class="size-5 animate-spin" />
        <span>
          {dgettext("projects", "A restoration is in progress. Please wait for it to complete.")}
        </span>
        <button phx-click="clear_stale_lock" class="btn btn-xs btn-ghost">
          {dgettext("projects", "Clear stale lock")}
        </button>
      </div>

      <%!-- Create Snapshot --%>
      <section>
        <div class="card bg-base-200 p-4">
          <.form for={@snapshot_form} id="snapshot-form" phx-submit="create_snapshot">
            <.input
              field={@snapshot_form[:title]}
              type="text"
              label={dgettext("projects", "Snapshot Title")}
              placeholder={dgettext("projects", "e.g., Before playtest v2")}
            />
            <.input
              field={@snapshot_form[:description]}
              type="textarea"
              label={dgettext("projects", "Description")}
              rows={2}
            />
            <.form_actions>
              <.button
                variant="primary"
                phx-disable-with={dgettext("projects", "Creating...")}
                disabled={!@can_create_snapshot || @restoration_in_progress}
              >
                <.icon name="archive" class="size-4" />
                {dgettext("projects", "Create Snapshot")}
              </.button>
            </.form_actions>
          </.form>
          <p :if={!@can_create_snapshot} class="text-sm text-error mt-2">
            {dgettext("projects", "Snapshot limit reached for your plan.")}
          </p>
        </div>
      </section>

      <div class="divider" />

      <%!-- Snapshot List --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Snapshots")}</h3>

        <.empty_state
          :if={@snapshots == []}
          icon="archive"
          title={dgettext("projects", "No snapshots yet")}
        >
          {dgettext(
            "projects",
            "Create a snapshot to save a point-in-time backup of your entire project."
          )}
        </.empty_state>

        <div :if={@snapshots != []} class="space-y-3">
          <div
            :for={snapshot <- @snapshots}
            class="card bg-base-200 p-4"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="badge badge-sm badge-ghost">
                    v{snapshot.version_number}
                  </span>
                  <span class="font-medium truncate">
                    {snapshot.title || dgettext("projects", "Untitled Snapshot")}
                  </span>
                </div>
                <p :if={snapshot.description} class="text-sm opacity-70 mt-1">
                  {snapshot.description}
                </p>
                <div class="flex flex-wrap gap-3 mt-2 text-xs opacity-60">
                  <span :if={snapshot.created_by}>
                    {snapshot.created_by.email}
                  </span>
                  <span>
                    {Calendar.strftime(snapshot.inserted_at, "%b %d, %Y %H:%M UTC")}
                  </span>
                  <span>
                    {format_snapshot_size(snapshot.snapshot_size_bytes)}
                  </span>
                  <span :for={{type, count} <- sorted_entity_counts(snapshot.entity_counts)}>
                    {count} {type}
                  </span>
                </div>
              </div>
              <div class="flex gap-2 shrink-0">
                <button
                  phx-click={show_modal("restore-snapshot-#{snapshot.id}")}
                  class="btn btn-xs btn-outline"
                  disabled={@restoration_in_progress}
                >
                  <.icon name="rotate-ccw" class="size-3" />
                  {dgettext("projects", "Restore")}
                </button>
                <button
                  phx-click={show_modal("delete-snapshot-#{snapshot.id}")}
                  class="btn btn-xs btn-outline btn-error"
                  disabled={@restoration_in_progress}
                >
                  <.icon name="trash-2" class="size-3" />
                </button>
              </div>
            </div>

            <.confirm_modal
              id={"restore-snapshot-#{snapshot.id}"}
              title={dgettext("projects", "Restore project snapshot?")}
              message={
                dgettext(
                  "projects",
                  "This will overwrite all current project data with the state from this snapshot. A safety snapshot will be created before restoring."
                )
              }
              confirm_text={dgettext("projects", "Restore")}
              confirm_variant="warning"
              icon="rotate-ccw"
              on_confirm={JS.push("restore_snapshot", value: %{id: snapshot.id})}
            />

            <.confirm_modal
              id={"delete-snapshot-#{snapshot.id}"}
              title={dgettext("projects", "Delete snapshot?")}
              message={
                dgettext(
                  "projects",
                  "This will permanently delete this snapshot. This action cannot be undone."
                )
              }
              confirm_text={dgettext("projects", "Delete")}
              confirm_variant="error"
              icon="trash-2"
              on_confirm={JS.push("delete_snapshot", value: %{id: snapshot.id})}
            />
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp section_content(%{live_action: :version_control} = assigns) do
    ~H"""
    <div class="space-y-8">
      <.form
        for={@version_control_form}
        id="version-control-form"
        phx-submit="save_version_control"
      >
        <%!-- Auto Daily Snapshots --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">
            {dgettext("projects", "Automatic Snapshots")}
          </h3>
          <div class="card bg-base-200 p-4">
            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="version_control[auto_snapshots_enabled]" value="false" />
              <input
                type="checkbox"
                name="version_control[auto_snapshots_enabled]"
                value="true"
                checked={@version_control_form[:auto_snapshots_enabled].value}
                class="checkbox checkbox-sm"
              />
              <div>
                <span class="font-medium">
                  {dgettext("projects", "Enable daily automatic snapshots")}
                </span>
                <p class="text-sm opacity-70">
                  {dgettext(
                    "projects",
                    "Creates a daily backup at 3:00 AM UTC when changes are detected."
                  )}
                </p>
              </div>
            </label>
          </div>
        </section>

        <div class="divider" />

        <%!-- Per-Entity Auto-Versioning --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">
            {dgettext("projects", "Auto-Versioning")}
          </h3>
          <p class="text-sm opacity-70 mb-4">
            {dgettext(
              "projects",
              "Automatically create version snapshots when editing entities."
            )}
          </p>
          <div class="card bg-base-200 p-4 space-y-3">
            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="version_control[auto_version_flows]" value="false" />
              <input
                type="checkbox"
                name="version_control[auto_version_flows]"
                value="true"
                checked={@version_control_form[:auto_version_flows].value}
                class="checkbox checkbox-sm"
              />
              <span>{dgettext("projects", "Flows")}</span>
            </label>
            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="version_control[auto_version_scenes]" value="false" />
              <input
                type="checkbox"
                name="version_control[auto_version_scenes]"
                value="true"
                checked={@version_control_form[:auto_version_scenes].value}
                class="checkbox checkbox-sm"
              />
              <span>{dgettext("projects", "Scenes")}</span>
            </label>
            <label class="flex items-center gap-3">
              <input type="hidden" name="version_control[auto_version_sheets]" value="false" />
              <input
                type="checkbox"
                name="version_control[auto_version_sheets]"
                value="true"
                checked={@version_control_form[:auto_version_sheets].value}
                class="checkbox checkbox-sm"
              />
              <span>{dgettext("projects", "Sheets")}</span>
            </label>
          </div>
        </section>

        <.form_actions>
          <.button variant="primary" phx-disable-with={dgettext("projects", "Saving...")}>
            {dgettext("projects", "Save Changes")}
          </.button>
        </.form_actions>
      </.form>

      <div :if={@version_usage} class="divider" />

      <%!-- Usage Breakdown --%>
      <section :if={@version_usage}>
        <h3 class="text-lg font-semibold mb-4">
          {dgettext("projects", "Usage")}
        </h3>
        <div class="space-y-4">
          <.usage_bar
            label={dgettext("projects", "Project Snapshots")}
            used={@version_usage.project_snapshots.used}
            limit={@version_usage.project_snapshots.limit}
          />
          <.usage_bar
            label={dgettext("projects", "Named Versions")}
            used={@version_usage.named_versions.used}
            limit={@version_usage.named_versions.limit}
          />
        </div>
      </section>
    </div>
    """
  end

  defp usage_bar(assigns) do
    pct =
      if assigns.limit && assigns.limit > 0,
        do: min(round(assigns.used / assigns.limit * 100), 100),
        else: 0

    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span>{@label}</span>
        <span class="opacity-70">{@used} / {@limit || "∞"}</span>
      </div>
      <progress class="progress progress-primary w-full" value={@pct} max="100" />
    </div>
    """
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) do
          members = Projects.list_project_members(project.id)

          project_changeset = Projects.change_project(project)
          provider_config = get_provider_config(project.id)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(:members, members)
            |> assign(:project_form, to_form(project_changeset))
            |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
            |> assign(
              :provider_form,
              to_form(provider_changeset(provider_config), as: "provider")
            )
            |> assign(
              :has_api_key,
              provider_config != nil && provider_config.api_key_encrypted != nil
            )
            |> assign(:provider_usage, nil)
            |> assign(:snapshots, [])
            |> assign(:snapshot_form, to_form(snapshot_changeset(%{}), as: "snapshot"))
            |> assign(:can_create_snapshot, true)
            |> assign(:version_control_form, nil)
            |> assign(:version_usage, nil)
            |> assign(:restoration_in_progress, restoration_in_progress?(project.id))
            |> assign_theme(project)
            |> maybe_subscribe_restoration(project.id)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             dgettext("projects", "You don't have permission to manage this project.")
           )
           |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    socket =
      socket
      |> assign(:page_title, dgettext("projects", "Project Settings"))
      |> assign(:current_path, current_path)
      |> maybe_load_snapshots()
      |> maybe_load_version_control()

    {:noreply, socket}
  end

  defp maybe_load_snapshots(%{assigns: %{live_action: :snapshots}} = socket) do
    project = socket.assigns.project

    socket
    |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
    |> assign(
      :can_create_snapshot,
      Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
    )
  end

  defp maybe_load_snapshots(socket), do: socket

  defp maybe_load_version_control(%{assigns: %{live_action: :version_control}} = socket) do
    project = socket.assigns.project

    socket
    |> assign(
      :version_control_form,
      to_form(version_control_changeset(project), as: "version_control")
    )
    |> assign(:version_usage, Billing.project_usage(project.id, project.workspace_id))
  end

  defp maybe_load_version_control(socket), do: socket

  defp version_control_changeset(project) do
    types = %{
      auto_snapshots_enabled: :boolean,
      auto_version_flows: :boolean,
      auto_version_scenes: :boolean,
      auto_version_sheets: :boolean
    }

    data = %{
      auto_snapshots_enabled: project.auto_snapshots_enabled,
      auto_version_flows: project.auto_version_flows,
      auto_version_scenes: project.auto_version_scenes,
      auto_version_sheets: project.auto_version_sheets
    }

    {data, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("validate_project", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(changeset))}
  end

  def handle_event("update_project", %{"project" => project_params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      case Projects.update_project(socket.assigns.project, project_params) do
        {:ok, project} ->
          project_changeset = Projects.change_project(project)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:project_form, to_form(project_changeset))
            |> put_flash(:info, dgettext("projects", "Project updated successfully."))

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :project_form, to_form(changeset))}
      end
    end)
  end

  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    with_authorization(socket, :manage_members, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    with_authorization(socket, :manage_members, fn socket ->
      do_remove_member(socket, id)
    end)
  end

  def handle_event("repair_variable_references", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_repair_variable_references(socket)
    end)
  end

  def handle_event("delete_project", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      workspace = socket.assigns.workspace

      case Projects.delete_project(socket.assigns.project, socket.assigns.current_scope.user.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("projects", "Project deleted."))
           |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete project."))}
      end
    end)
  end

  def handle_event("create_snapshot", %{"snapshot" => params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_create_snapshot(socket, params)
    end)
  end

  def handle_event("restore_snapshot", %{"id" => id}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_restore_snapshot(socket, id)
    end)
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_delete_snapshot(socket, id)
    end)
  end

  def handle_event("save_version_control", %{"version_control" => params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      # Checkboxes: absent = false, present = true
      attrs = %{
        auto_snapshots_enabled: params["auto_snapshots_enabled"] == "true",
        auto_version_flows: params["auto_version_flows"] == "true",
        auto_version_scenes: params["auto_version_scenes"] == "true",
        auto_version_sheets: params["auto_version_sheets"] == "true"
      }

      case Projects.update_project(socket.assigns.project, attrs) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(
             :version_control_form,
             to_form(version_control_changeset(project), as: "version_control")
           )
           |> put_flash(:info, dgettext("projects", "Version control settings saved."))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save settings."))}
      end
    end)
  end

  def handle_event("save_provider_config", %{"provider" => params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_save_provider_config(socket, params)
    end)
  end

  def handle_event("test_provider_connection", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_test_provider_connection(socket)
    end)
  end

  def handle_event("update_theme_primary", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_primary, color)}
  end

  def handle_event("update_theme_accent", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_accent, color)}
  end

  def handle_event("save_theme", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      project = socket.assigns.project
      settings = project.settings || %{}

      new_settings =
        Map.put(settings, "theme", %{
          "primary" => socket.assigns.theme_primary,
          "accent" => socket.assigns.theme_accent
        })

      case Projects.update_project(project, %{settings: new_settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(:has_custom_theme, true)
           |> put_flash(:info, dgettext("projects", "Theme saved."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save theme."))}
      end
    end)
  end

  def handle_event("reset_theme", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      project = socket.assigns.project
      settings = Map.delete(project.settings || %{}, "theme")

      case Projects.update_project(project, %{settings: settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign_theme(project)
           |> put_flash(:info, dgettext("projects", "Theme reset to default."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to reset theme."))}
      end
    end)
  end

  def handle_event("clear_stale_lock", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      case Projects.clear_stale_restoration_lock(socket.assigns.project.id) do
        {:ok, :cleared} ->
          {:noreply,
           socket
           |> assign(:restoration_in_progress, false)
           |> put_flash(:info, dgettext("projects", "Stale restoration lock cleared."))}

        {:error, :not_stale} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Lock is not stale yet. Please wait or let the restore finish.")
           )}
      end
    end)
  end

  # ===========================================================================
  # Handle Info (restoration events)
  # ===========================================================================

  @impl true
  def handle_info({:project_restoration_started, _payload}, socket) do
    {:noreply, assign(socket, :restoration_in_progress, true)}
  end

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
     |> assign(
       :can_create_snapshot,
       Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
     )
     |> put_flash(
       :info,
       dgettext(
         "projects",
         "Project restored. %{restored} entities restored, %{skipped} skipped.",
         restored: payload.restored,
         skipped: payload.skipped
       )
     )}
  end

  @impl true
  def handle_info({:project_restoration_failed, _payload}, socket) do
    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> put_flash(
       :error,
       dgettext("projects", "Project restoration failed. Please try again.")
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===========================================================================
  # Private
  # ===========================================================================

  defp section_title(:general), do: dgettext("projects", "General")
  defp section_title(:localization), do: dgettext("projects", "Localization")
  defp section_title(:members), do: dgettext("projects", "Members")
  defp section_title(:snapshots), do: dgettext("projects", "Snapshots")
  defp section_title(:version_control), do: dgettext("projects", "Version Control")

  defp section_subtitle(:general),
    do: dgettext("projects", "Project details, theme, and maintenance")

  defp section_subtitle(:localization),
    do: dgettext("projects", "Translation provider configuration")

  defp section_subtitle(:members),
    do: dgettext("projects", "Manage project members and invitations")

  defp section_subtitle(:snapshots),
    do: dgettext("projects", "Create and restore point-in-time project backups")

  defp section_subtitle(:version_control),
    do: dgettext("projects", "Configure automatic snapshots and auto-versioning")

  @entity_type_order ~w(sheets flows scenes languages localized_texts glossary_entries)
  defp sorted_entity_counts(counts) when is_map(counts) do
    for type <- @entity_type_order,
        count = Map.get(counts, type, 0),
        count > 0,
        do: {type, count}
  end

  defp sorted_entity_counts(_), do: []

  defp maybe_subscribe_restoration(socket, project_id) do
    if connected?(socket), do: Collaboration.subscribe_restoration(project_id)
    socket
  end

  defp restoration_in_progress?(project_id) do
    case Projects.restoration_in_progress?(project_id) do
      {true, _} -> true
      _ -> false
    end
  end

  defp assign_theme(socket, project) do
    case Storyarn.Projects.Project.theme_colors(project) do
      %{primary: p, accent: a} ->
        socket
        |> assign(:theme_primary, p)
        |> assign(:theme_accent, a)
        |> assign(:has_custom_theme, true)

      nil ->
        socket
        |> assign(:theme_primary, "#00D4CC")
        |> assign(:theme_accent, "#E8922F")
        |> assign(:has_custom_theme, false)
    end
  end
end
