defmodule StoryarnWeb.Components.VersionsSection do
  @moduledoc """
  Shared LiveComponent for version history management.
  Works with any entity type (sheet, flow, scene) through the generalized Versioning context.
  """

  use StoryarnWeb, :live_component
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Versioning

  @versions_per_page 20

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold flex items-center gap-2">
          <.icon name="history" class="size-5" />
          {dgettext("versioning", "Version History")}
        </h2>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="show_create_version_modal"
          phx-target={@myself}
        >
          <.icon name="plus" class="size-4" />
          {dgettext("versioning", "Create Version")}
        </button>
      </div>

      <%= if is_nil(@versions) do %>
        <.loading_placeholder />
      <% else %>
        <%= if @versions == [] do %>
          <.empty_versions_state />
        <% else %>
          <div class="space-y-2">
            <.version_row
              :for={version <- @versions}
              version={version}
              is_current={version.id == @current_version_id}
              can_edit={@can_edit}
              target={@myself}
            />
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
      |> assign_new(:versions_page, fn -> 1 end)
      |> assign_new(:has_more_versions, fn -> false end)
      |> assign_new(:show_create_version_modal, fn -> false end)
      |> assign_new(:current_version_id, fn -> nil end)

    socket =
      if is_nil(socket.assigns.versions) do
        load_versions(socket, 1)
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

  def handle_event("restore_version", %{"version" => version_number}, socket) do
    with_edit_authorization(socket, fn socket ->
      restore_version(socket, version_number)
    end)
  end

  def handle_event("set_pending_delete_version", %{"version" => version_number}, socket) do
    {:noreply, assign(socket, :pending_delete_version, version_number)}
  end

  def handle_event("confirm_delete_version", _params, socket) do
    if version = socket.assigns[:pending_delete_version] do
      handle_event("delete_version", %{"version" => to_string(version)}, socket)
    else
      {:noreply, socket}
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
    entity = socket.assigns.entity
    entity_type = socket.assigns.entity_type
    user_id = socket.assigns.current_user_id
    project_id = socket.assigns.project_id

    title = if title == "", do: nil, else: title
    description = if description == "", do: nil, else: description

    case Versioning.create_version(entity_type, entity, project_id, user_id,
           title: title,
           description: description
         ) do
      {:ok, version} ->
        socket =
          socket
          |> load_versions(1)
          |> assign(:show_create_version_modal, false)

        notify_parent(:version_created, %{version: version})
        {:noreply, put_flash(socket, :info, dgettext("versioning", "Version created."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
    end
  end

  defp restore_version(socket, version_number) do
    case parse_version_number(version_number) do
      {:ok, number} ->
        entity_type = socket.assigns.entity_type
        entity_id = socket.assigns.entity.id

        case Versioning.get_version(entity_type, entity_id, number) do
          nil ->
            {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}

          version ->
            restore_from_version(socket, version)
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Invalid version number."))}
    end
  end

  defp restore_from_version(socket, version) do
    entity = socket.assigns.entity
    entity_type = socket.assigns.entity_type

    case Versioning.restore_version(entity_type, entity, version) do
      {:ok, updated_entity} ->
        socket = load_versions(socket, 1)

        notify_parent(:version_restored, %{
          entity: updated_entity,
          version: version
        })

        {:noreply,
         put_flash(
           socket,
           :info,
           dgettext("versioning", "Restored to version %{number}", number: version.version_number)
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
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
        socket = load_versions(socket, 1)
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

    socket
    |> assign(:versions, versions)
    |> assign(:versions_page, page_number)
    |> assign(:has_more_versions, has_more)
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
  attr :is_current, :boolean, default: false
  attr :can_edit, :boolean, default: false
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
        !@is_current && "bg-base-300"
      ]}>
        v{@version.version_number}
      </div>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium">
            {@version.title || @version.change_summary || dgettext("versioning", "No summary")}
          </span>
          <span :if={@is_current} class="badge badge-primary badge-sm">
            {dgettext("versioning", "Current")}
          </span>
        </div>
        <p :if={@version.description} class="text-sm text-base-content/70 mt-0.5">
          {@version.description}
        </p>
        <div class="flex items-center gap-2 text-xs text-base-content/60 mt-0.5">
          <span>{format_version_date(@version.inserted_at)}</span>
          <span :if={@version.created_by}>
            · {dgettext("versioning", "by")} {@version.created_by.display_name || @version.created_by.email}
          </span>
        </div>
      </div>
      <div
        :if={@can_edit}
        class="flex-shrink-0 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
      >
        <button
          :if={!@is_current}
          type="button"
          class="btn btn-ghost btn-xs tooltip"
          data-tip={dgettext("versioning", "Restore this version")}
          phx-click="restore_version"
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
