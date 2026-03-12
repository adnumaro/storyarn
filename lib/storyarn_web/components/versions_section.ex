defmodule StoryarnWeb.Components.VersionsSection do
  @moduledoc """
  Shared LiveComponent for version history management.
  Works with any entity type (sheet, flow, scene) through the generalized Versioning context.

  Displays named versions (milestones) prominently at top, with auto-snapshots
  in a collapsible section below. Supports promoting auto-snapshots to named versions.
  """

  use StoryarnWeb, :live_component
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Billing
  alias Storyarn.Versioning

  @versions_per_page 20

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <%= if is_nil(@versions) do %>
        <.loading_placeholder />
      <% else %>
        <%= if @versions == [] do %>
          <.empty_versions_state />
        <% else %>
          <%!-- Named Versions --%>
          <div :if={@named_versions != []} class="space-y-2 mb-6">
            <h3 class="text-sm font-medium text-base-content/70 flex items-center gap-1.5">
              <.icon name="bookmark" class="size-4" />
              {dgettext("versioning", "Named Versions")}
            </h3>
            <.version_row
              :for={version <- @named_versions}
              version={version}
              variant={:named}
              is_current={version.id == @current_version_id}
              can_edit={@can_edit}
              can_name_version={@can_name_version}
              target={@myself}
            />
          </div>

          <%!-- Auto History --%>
          <div :if={@auto_versions != []}>
            <button
              type="button"
              class="text-sm text-base-content/60 flex items-center gap-1.5 mb-2 hover:text-base-content/80 transition-colors"
              phx-click="toggle_auto_versions"
              phx-target={@myself}
            >
              <.icon
                name={if @show_auto_versions, do: "chevron-down", else: "chevron-right"}
                class="size-4"
              />
              {dngettext(
                "versioning",
                "%{count} auto-save",
                "%{count} auto-saves",
                length(@auto_versions),
                count: length(@auto_versions)
              )}
            </button>
            <div :if={@show_auto_versions} class="space-y-2">
              <.version_row
                :for={version <- @auto_versions}
                version={version}
                variant={:auto}
                is_current={version.id == @current_version_id}
                can_edit={@can_edit}
                can_name_version={@can_name_version}
                target={@myself}
              />
            </div>
          </div>

          <button
            :if={@has_more_versions}
            type="button"
            class="btn btn-ghost btn-sm w-full mt-4"
            phx-click="load_more_versions"
            phx-target={@myself}
          >
            <.icon name="chevron-down" class="size-4" />
            {dgettext("versioning", "Load more")}
          </button>
        <% end %>
      <% end %>

      <%!-- Create Version Modal --%>
      <.modal
        :if={@show_create_version_modal}
        id="create-version-modal"
        show
        on_cancel={JS.push("hide_create_version_modal", target: @myself)}
      >
        <.create_version_form target={@myself} />
      </.modal>

      <%!-- Promote Version Modal --%>
      <.modal
        :if={@promote_version != nil}
        id="promote-version-modal"
        show
        on_cancel={JS.push("hide_promote_modal", target: @myself)}
      >
        <.promote_version_form version={@promote_version} target={@myself} />
      </.modal>

      <%!-- Restore Conflict Modal --%>
      <.modal
        :if={@restore_preview != nil}
        id="restore-conflict-modal"
        show
        on_cancel={JS.push("cancel_restore", target: @myself)}
      >
        <.restore_preview_content
          preview={@restore_preview}
          target={@myself}
        />
      </.modal>

      <.confirm_modal
        :if={@can_edit}
        id={"delete-version-confirm-#{@entity_type}"}
        title={dgettext("versioning", "Delete version?")}
        message={dgettext("versioning", "Are you sure you want to delete this version?")}
        confirm_text={dgettext("versioning", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_version", target: @myself)}
      />
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:versions, fn -> nil end)
      |> assign_new(:named_versions, fn -> [] end)
      |> assign_new(:auto_versions, fn -> [] end)
      |> assign_new(:versions_page, fn -> 1 end)
      |> assign_new(:has_more_versions, fn -> false end)
      |> assign_new(:show_create_version_modal, fn -> false end)
      |> assign_new(:show_auto_versions, fn -> false end)
      |> assign_new(:promote_version, fn -> nil end)
      |> assign_new(:current_version_id, fn -> nil end)
      |> assign_new(:can_name_version, fn -> true end)
      |> assign_new(:limit_message, fn -> nil end)
      |> assign_new(:pending_delete_version, fn -> nil end)
      |> assign_new(:restore_preview, fn -> nil end)
      |> assign_new(:restore_loading, fn -> false end)

    socket =
      if is_nil(socket.assigns.versions) do
        socket
        |> load_versions(1)
        |> check_named_version_limit()
      else
        socket
      end

    {:ok, socket}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("show_create_version_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_version_modal, true)}
  end

  def handle_event("hide_create_version_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_version_modal, false)}
  end

  def handle_event("create_version", %{"title" => title, "description" => description}, socket) do
    with_edit_authorization(socket, fn socket ->
      create_version(socket, title, description)
    end)
  end

  def handle_event("toggle_auto_versions", _params, socket) do
    {:noreply, assign(socket, :show_auto_versions, !socket.assigns.show_auto_versions)}
  end

  def handle_event("show_promote_modal", %{"version" => version_number}, socket) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        version =
          Enum.find(socket.assigns.versions, &(&1.version_number == number))

        {:noreply, assign(socket, :promote_version, version)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("hide_promote_modal", _params, socket) do
    {:noreply, assign(socket, :promote_version, nil)}
  end

  def handle_event("promote_version", params, socket) do
    with_edit_authorization(socket, fn socket ->
      promote_version(
        socket,
        params["version_number"],
        params["title"],
        params["description"]
      )
    end)
  end

  def handle_event("preview_restore", %{"version" => version_number}, socket) do
    with_edit_authorization(socket, fn socket ->
      preview_restore(socket, version_number)
    end)
  end

  def handle_event("confirm_restore", _params, socket) do
    with_edit_authorization(socket, fn socket ->
      confirm_restore(socket)
    end)
  end

  def handle_event("cancel_restore", _params, socket) do
    {:noreply, assign(socket, :restore_preview, nil)}
  end

  def handle_event("set_pending_delete_version", %{"version" => version_number}, socket) do
    {:noreply, assign(socket, :pending_delete_version, version_number)}
  end

  def handle_event("confirm_delete_version", _params, socket) do
    case socket.assigns.pending_delete_version do
      nil ->
        {:noreply, socket}

      version_number ->
        with_edit_authorization(socket, fn socket ->
          delete_version(socket, to_string(version_number))
        end)
    end
  end

  def handle_event("delete_version", %{"version" => version_number}, socket) do
    with_edit_authorization(socket, fn socket ->
      delete_version(socket, version_number)
    end)
  end

  def handle_event("load_more_versions", _params, socket) do
    next_page = socket.assigns.versions_page + 1
    {:noreply, load_versions(socket, next_page)}
  end

  # ===========================================================================
  # Private: Version Operations
  # ===========================================================================

  defp create_version(socket, title, description) do
    title = if title == "", do: nil, else: title
    description = if description == "", do: nil, else: description

    if title != nil and not check_named_version_allowed?(socket) do
      {:noreply,
       put_flash(socket, :error, dgettext("versioning", "Named version limit reached."))}
    else
      do_create_version(socket, title, description)
    end
  end

  defp do_create_version(socket, title, description) do
    entity = socket.assigns.entity
    entity_type = socket.assigns.entity_type
    user_id = socket.assigns.current_user_id
    project_id = socket.assigns.project_id

    case Versioning.create_version(entity_type, entity, project_id, user_id,
           title: title,
           description: description
         ) do
      {:ok, version} ->
        socket =
          socket
          |> load_versions(1)
          |> check_named_version_limit()
          |> assign(:show_create_version_modal, false)

        notify_parent(:version_created, %{version: version})
        {:noreply, put_flash(socket, :info, dgettext("versioning", "Version created."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
    end
  end

  defp promote_version(socket, version_number, title, description) do
    entity_type = socket.assigns.entity_type
    entity_id = socket.assigns.entity.id

    with {:ok, number} <- parse_version_number(version_number),
         version when not is_nil(version) <-
           Versioning.get_version(entity_type, entity_id, number),
         true <- check_named_version_allowed?(socket) do
      title = if title == "", do: nil, else: title
      description = if description == "", do: nil, else: description

      case Versioning.update_version(version, %{title: title, description: description}) do
        {:ok, _updated} ->
          socket =
            socket
            |> load_versions(1)
            |> check_named_version_limit()
            |> assign(:promote_version, nil)

          {:noreply,
           put_flash(socket, :info, dgettext("versioning", "Version named successfully."))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
      end
    else
      :error ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Invalid version number."))}

      nil ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}

      false ->
        {:noreply,
         put_flash(socket, :error, dgettext("versioning", "Named version limit reached."))}
    end
  end

  defp preview_restore(socket, version_number) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        entity_type = socket.assigns.entity_type
        entity_id = socket.assigns.entity.id

        case Versioning.get_version(entity_type, entity_id, number) do
          nil ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}

          version ->
            detect_and_show_preview(socket, version)
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Invalid version number."))}
    end
  end

  defp detect_and_show_preview(socket, version) do
    entity = socket.assigns.entity
    entity_type = socket.assigns.entity_type

    case Versioning.load_version_snapshot(version) do
      {:ok, snapshot} ->
        report = Versioning.detect_restore_conflicts(entity_type, snapshot, entity)

        preview = %{
          version: version,
          report: report
        }

        {:noreply, assign(socket, :restore_preview, preview)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("versioning", "Could not load version snapshot."))}
    end
  end

  defp confirm_restore(socket) do
    case socket.assigns.restore_preview do
      nil ->
        {:noreply, socket}

      %{version: version} ->
        entity = socket.assigns.entity
        entity_type = socket.assigns.entity_type
        user_id = socket.assigns.current_user_id

        case Versioning.restore_version(entity_type, entity, version, user_id: user_id) do
          {:ok, updated_entity} ->
            socket =
              socket
              |> assign(:restore_preview, nil)
              |> load_versions(1)
              |> check_named_version_limit()

            notify_parent(:version_restored, %{
              entity: updated_entity,
              version: version
            })

            {:noreply,
             put_flash(
               socket,
               :info,
               dgettext("versioning", "Restored to version %{number}",
                 number: version.version_number
               )
             )}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:restore_preview, nil)
             |> put_flash(:error, dgettext("versioning", "Could not restore version."))}
        end
    end
  end

  defp delete_version(socket, version_number) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        entity_type = socket.assigns.entity_type
        entity_id = socket.assigns.entity.id

        case Versioning.get_version(entity_type, entity_id, number) do
          nil ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}

          version ->
            do_delete_version(socket, version)
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Invalid version number."))}
    end
  end

  defp do_delete_version(socket, version) do
    case Versioning.delete_version(version) do
      {:ok, _} ->
        socket =
          socket
          |> load_versions(1)
          |> check_named_version_limit()

        notify_parent(:version_deleted, %{version: version})
        {:noreply, put_flash(socket, :info, dgettext("versioning", "Version deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
    end
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_versions(socket, page_number) do
    entity_type = socket.assigns.entity_type
    entity_id = socket.assigns.entity.id
    offset = (page_number - 1) * @versions_per_page

    versions =
      Versioning.list_versions(entity_type, entity_id,
        limit: @versions_per_page + 1,
        offset: offset
      )

    has_more = length(versions) > @versions_per_page
    versions = Enum.take(versions, @versions_per_page)

    versions =
      if page_number > 1 and not is_nil(socket.assigns.versions) do
        socket.assigns.versions ++ versions
      else
        versions
      end

    {named, auto} = Enum.split_with(versions, &(not is_nil(&1.title)))

    socket
    |> assign(:versions, versions)
    |> assign(:named_versions, named)
    |> assign(:auto_versions, auto)
    |> assign(:versions_page, page_number)
    |> assign(:has_more_versions, has_more)
  end

  defp check_named_version_allowed?(socket) do
    case socket.assigns[:workspace_id] do
      nil ->
        true

      workspace_id ->
        Billing.can_create_named_version?(socket.assigns.project_id, workspace_id) == :ok
    end
  end

  defp check_named_version_limit(socket) do
    project_id = socket.assigns.project_id
    workspace_id = socket.assigns[:workspace_id]

    if workspace_id do
      case Billing.can_create_named_version?(project_id, workspace_id) do
        :ok ->
          assign(socket, can_name_version: true, limit_message: nil)

        {:error, :limit_reached, %{used: used, limit: limit}} ->
          message =
            dgettext("versioning", "Named version limit reached (%{used}/%{limit})",
              used: used,
              limit: limit
            )

          assign(socket, can_name_version: false, limit_message: message)
      end
    else
      assign(socket, can_name_version: true, limit_message: nil)
    end
  end

  # ===========================================================================
  # Private: Parent Notifications
  # ===========================================================================

  defp notify_parent(action, data) do
    send(self(), {:versions_section, action, data})
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  defp loading_placeholder(assigns) do
    ~H"""
    <div class="flex items-center justify-center p-8">
      <span class="loading loading-spinner loading-md"></span>
    </div>
    """
  end

  defp empty_versions_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-lg p-8 text-center">
      <.icon name="clock" class="size-12 mx-auto text-base-content/30 mb-4" />
      <p class="text-base-content/70 mb-2">{dgettext("versioning", "No versions yet")}</p>
      <p class="text-sm text-base-content/50">
        {dgettext("versioning", "Create a version to save the current state.")}
      </p>
    </div>
    """
  end

  attr :version, :map, required: true
  attr :variant, :atom, default: :named
  attr :is_current, :boolean, default: false
  attr :can_edit, :boolean, default: false
  attr :can_name_version, :boolean, default: true
  attr :target, :any, default: nil

  defp version_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-4 p-3 rounded-lg group",
      @is_current && "bg-primary/10 border border-primary/30",
      !@is_current && "hover:bg-base-200/50"
    ]}>
      <div class={[
        "flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center text-sm font-medium",
        @is_current && "bg-primary text-primary-content",
        @variant == :named && !@is_current && "bg-accent/20 text-accent",
        @variant == :auto && !@is_current && "bg-base-300"
      ]}>
        <%= if @variant == :named do %>
          <.icon name="bookmark" class="size-4" />
        <% else %>
          <span class="text-xs">v{@version.version_number}</span>
        <% end %>
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class={[
            "text-sm",
            @variant == :named && "font-medium",
            @variant == :auto && "text-base-content/70"
          ]}>
            {@version.title || @version.change_summary || dgettext("versioning", "No summary")}
          </span>
          <span :if={@is_current} class="badge badge-primary badge-sm">
            {dgettext("versioning", "Current")}
          </span>
          <span :if={@variant == :named} class="badge badge-accent badge-xs badge-outline">
            v{@version.version_number}
          </span>
        </div>
        <p
          :if={@variant == :named && @version.description}
          class="text-sm text-base-content/70 mt-0.5"
        >
          {@version.description}
        </p>
        <p
          :if={@variant == :named && @version.change_summary}
          class="text-xs text-base-content/50 mt-0.5"
        >
          {@version.change_summary}
        </p>
        <div class="flex items-center gap-2 text-xs text-base-content/60 mt-0.5">
          <span>{format_version_date(@version.inserted_at)}</span>
          <span :if={@version.created_by}>
            · {dgettext("versioning", "by")} {@version.created_by.display_name ||
              @version.created_by.email}
          </span>
        </div>
      </div>
      <div
        :if={@can_edit}
        class="flex-shrink-0 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
      >
        <button
          :if={@variant == :auto && @can_name_version}
          type="button"
          class="btn btn-ghost btn-xs tooltip"
          data-tip={dgettext("versioning", "Name this version")}
          phx-click="show_promote_modal"
          phx-value-version={@version.version_number}
          phx-target={@target}
        >
          <.icon name="bookmark-plus" class="size-4" />
        </button>
        <button
          :if={!@is_current}
          type="button"
          class="btn btn-ghost btn-xs tooltip"
          data-tip={dgettext("versioning", "Restore this version")}
          phx-click="preview_restore"
          phx-value-version={@version.version_number}
          phx-target={@target}
        >
          <.icon name="rotate-ccw" class="size-4" />
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs tooltip text-error"
          data-tip={dgettext("versioning", "Delete version")}
          phx-click={
            JS.push("set_pending_delete_version",
              value: %{version: @version.version_number},
              target: @target
            )
            |> show_modal("delete-version-confirm-#{@version.entity_type}")
          }
        >
          <.icon name="trash-2" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :target, :any, default: nil

  defp create_version_form(assigns) do
    ~H"""
    <h3 class="font-bold text-lg mb-4">{dgettext("versioning", "Create Version")}</h3>
    <form phx-submit="create_version" phx-target={@target}>
      <div class="mb-4">
        <label class="label" for="version-title">
          <span class="label-text">{dgettext("versioning", "Title")}</span>
        </label>
        <input
          type="text"
          name="title"
          id="version-title"
          class="input input-bordered w-full"
          placeholder={dgettext("versioning", "e.g., Before major refactor")}
          required
          autofocus
        />
      </div>
      <div class="mb-4">
        <label class="label" for="version-description">
          <span class="label-text">
            {dgettext("versioning", "Description")} ({dgettext("versioning", "optional")})
          </span>
        </label>
        <textarea
          name="description"
          id="version-description"
          class="textarea textarea-bordered w-full"
          rows="3"
          placeholder={dgettext("versioning", "Describe what this version captures...")}
        ></textarea>
      </div>
      <div class="modal-action">
        <button
          type="button"
          class="btn btn-ghost"
          phx-click="hide_create_version_modal"
          phx-target={@target}
        >
          {dgettext("versioning", "Cancel")}
        </button>
        <button type="submit" class="btn btn-primary">
          <.icon name="save" class="size-4" />
          {dgettext("versioning", "Create Version")}
        </button>
      </div>
    </form>
    """
  end

  attr :version, :map, required: true
  attr :target, :any, default: nil

  defp promote_version_form(assigns) do
    ~H"""
    <h3 class="font-bold text-lg mb-4">{dgettext("versioning", "Name This Version")}</h3>
    <p class="text-sm text-base-content/70 mb-4">
      {dgettext("versioning", "Give this auto-save a name to make it a milestone.")}
    </p>
    <form phx-submit="promote_version" phx-target={@target}>
      <input type="hidden" name="version_number" value={@version.version_number} />
      <div class="mb-4">
        <label class="label" for="promote-version-title">
          <span class="label-text">{dgettext("versioning", "Title")}</span>
        </label>
        <input
          type="text"
          name="title"
          id="promote-version-title"
          class="input input-bordered w-full"
          placeholder={
            @version.change_summary || dgettext("versioning", "e.g., Before major refactor")
          }
          required
          autofocus
        />
      </div>
      <div class="mb-4">
        <label class="label" for="promote-version-description">
          <span class="label-text">
            {dgettext("versioning", "Description")} ({dgettext("versioning", "optional")})
          </span>
        </label>
        <textarea
          name="description"
          id="promote-version-description"
          class="textarea textarea-bordered w-full"
          rows="3"
          placeholder={dgettext("versioning", "Describe what this version captures...")}
        ></textarea>
      </div>
      <div class="modal-action">
        <button
          type="button"
          class="btn btn-ghost"
          phx-click="hide_promote_modal"
          phx-target={@target}
        >
          {dgettext("versioning", "Cancel")}
        </button>
        <button type="submit" class="btn btn-primary">
          <.icon name="bookmark-plus" class="size-4" />
          {dgettext("versioning", "Name Version")}
        </button>
      </div>
    </form>
    """
  end

  attr :preview, :map, required: true
  attr :target, :any, default: nil

  defp restore_preview_content(assigns) do
    ~H"""
    <h3 class="font-bold text-lg mb-4 flex items-center gap-2">
      <.icon name="rotate-ccw" class="size-5" />
      {dgettext("versioning", "Restore to version %{number}", number: @preview.version.version_number)}
    </h3>

    <%= if @preview.report.has_conflicts do %>
      <div class="space-y-3 mb-4">
        <%!-- Shortcut collision --%>
        <div :if={@preview.report.shortcut_collision} class="alert alert-warning">
          <.icon name="alert-triangle" class="size-4" />
          <span>
            {dgettext("versioning", "Shortcut collision — will be renamed to \"%{shortcut}\"",
              shortcut: @preview.report.resolved_shortcut
            )}
          </span>
        </div>

        <%!-- Missing references --%>
        <div :if={@preview.report.conflicts != []} class="space-y-2">
          <p class="text-sm font-medium text-warning">
            <.icon name="alert-triangle" class="size-4 inline" />
            {dgettext("versioning", "Some referenced entities no longer exist:")}
          </p>

          <div
            :for={conflict <- @preview.report.conflicts}
            class="bg-base-200/50 rounded-lg p-3"
          >
            <div class="flex items-center gap-2 text-sm font-medium">
              <.icon name={conflict_type_icon(conflict.type)} class="size-4 text-warning" />
              <span>
                {dgettext("versioning", "Missing %{type} (ID: %{id})",
                  type: conflict_type_label(conflict.type),
                  id: conflict.id
                )}
              </span>
            </div>
            <ul class="mt-1 ml-6 text-xs text-base-content/60 list-disc">
              <li :for={context <- conflict.contexts}>{context}</li>
            </ul>
          </div>
        </div>

        <p class="text-sm text-base-content/70">
          {dgettext(
            "versioning",
            "Missing references will be cleared. Current state will be saved as a backup."
          )}
        </p>
      </div>
    <% else %>
      <p class="text-base-content/70 mb-4">
        {dgettext(
          "versioning",
          "Current state will be saved as a backup before restoring."
        )}
      </p>
    <% end %>

    <%!-- Auto-resolved items --%>
    <div
      :if={@preview.report.auto_resolved != []}
      class="bg-info/10 border border-info/20 rounded-lg p-3 mb-4"
    >
      <p class="text-sm font-medium text-info mb-1">
        <.icon name="info" class="size-4 inline" />
        {dgettext("versioning", "Auto-resolved:")}
      </p>
      <ul class="text-xs text-base-content/70 list-disc ml-5">
        <li :for={item <- @preview.report.auto_resolved}>{item}</li>
      </ul>
    </div>

    <div class="modal-action">
      <button
        type="button"
        class="btn btn-ghost"
        phx-click="cancel_restore"
        phx-target={@target}
      >
        {dgettext("versioning", "Cancel")}
      </button>
      <button
        type="button"
        class={[
          "btn",
          @preview.report.has_conflicts && "btn-warning",
          !@preview.report.has_conflicts && "btn-primary"
        ]}
        phx-click="confirm_restore"
        phx-target={@target}
      >
        <.icon name="rotate-ccw" class="size-4" />
        <%= if @preview.report.has_conflicts do %>
          {dgettext("versioning", "Restore anyway")}
        <% else %>
          {dgettext("versioning", "Restore")}
        <% end %>
      </button>
    </div>
    """
  end

  defp conflict_type_icon(:asset), do: "image"
  defp conflict_type_icon(:sheet), do: "file-text"
  defp conflict_type_icon(:flow), do: "git-branch"
  defp conflict_type_icon(:scene), do: "map"
  defp conflict_type_icon(:block), do: "puzzle"
  defp conflict_type_icon(_), do: "circle-alert"

  defp conflict_type_label(:asset), do: dgettext("versioning", "asset")
  defp conflict_type_label(:sheet), do: dgettext("versioning", "sheet")
  defp conflict_type_label(:flow), do: dgettext("versioning", "flow")
  defp conflict_type_label(:scene), do: dgettext("versioning", "scene")
  defp conflict_type_label(:block), do: dgettext("versioning", "block")
  defp conflict_type_label(_), do: dgettext("versioning", "entity")

  defp format_version_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end

  defp parse_version_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_version_number(value) when is_integer(value), do: {:ok, value}
  defp parse_version_number(_), do: :error
end
