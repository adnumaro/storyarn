defmodule StoryarnWeb.SheetLive.Components.VersionsSection do
  @moduledoc """
  LiveComponent for version history management.
  Handles listing, creating, restoring, and deleting versions.
  """

  use StoryarnWeb, :live_component
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Sheets

  @versions_per_page 20

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold flex items-center gap-2">
          <.icon name="history" class="size-5" />
          {dgettext("sheets", "Version History")}
        </h2>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="show_create_version_modal"
          phx-target={@myself}
        >
          <.icon name="plus" class="size-4" />
          {dgettext("sheets", "Create Version")}
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
              is_current={version.id == @sheet.current_version_id}
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
            {dgettext("sheets", "Load more")}
          </button>
        <% end %>
      <% end %>

      <%!-- Create Version Modal --%>
      <.create_version_modal :if={@show_create_version_modal} target={@myself} />

      <.confirm_modal
        :if={@can_edit}
        id="delete-version-confirm"
        title={dgettext("sheets", "Delete version?")}
        message={dgettext("sheets", "Are you sure you want to delete this version?")}
        confirm_text={dgettext("sheets", "Delete")}
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
    sheet = socket.assigns.sheet
    user_id = socket.assigns.current_user_id

    title = if title == "", do: nil, else: title
    description = if description == "", do: nil, else: description

    case Sheets.create_version(sheet, user_id, title: title, description: description) do
      {:ok, version} ->
        {:ok, _updated_sheet} = Sheets.set_current_version(sheet, version)

        updated_sheet =
          Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

        socket =
          socket
          |> assign(:sheet, updated_sheet)
          |> load_versions(1)
          |> assign(:show_create_version_modal, false)

        notify_parent(:sheet_updated, updated_sheet)
        notify_parent(:saved)
        {:noreply, put_flash(socket, :info, dgettext("sheets", "Version created."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create version."))}
    end
  end

  defp restore_version(socket, version_number) do
    version_number = String.to_integer(version_number)

    case Sheets.get_version(socket.assigns.sheet.id, version_number) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Version not found."))}

      version ->
        restore_from_version(socket, version)
    end
  end

  defp restore_from_version(socket, version) do
    sheet = socket.assigns.sheet

    case Sheets.restore_version(sheet, version) do
      {:ok, _updated_sheet} ->
        updated_sheet =
          Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

        socket =
          socket
          |> assign(:sheet, updated_sheet)
          |> load_versions(1)

        notify_parent(:version_restored, %{
          sheet: updated_sheet,
          version_number: version.version_number
        })

        {:noreply,
         socket
         |> push_event("restore_sheet_content", %{
           name: updated_sheet.name,
           shortcut: updated_sheet.shortcut || ""
         })
         |> put_flash(
           :info,
           dgettext("sheets", "Restored to version %{number}", number: version.version_number)
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not restore version."))}
    end
  end

  defp delete_version(socket, version_number) do
    version_number = String.to_integer(version_number)

    case Sheets.get_version(socket.assigns.sheet.id, version_number) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Version not found."))}

      version ->
        do_delete_version(socket, version)
    end
  end

  defp do_delete_version(socket, version) do
    case Sheets.delete_version(version) do
      {:ok, _} ->
        sheet = Sheets.get_sheet_full!(socket.assigns.project.id, socket.assigns.sheet.id)

        socket =
          socket
          |> assign(:sheet, sheet)
          |> load_versions(1)

        notify_parent(:sheet_updated, sheet)
        {:noreply, put_flash(socket, :info, dgettext("sheets", "Version deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete version."))}
    end
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_versions(socket, page_number) do
    offset = (page_number - 1) * @versions_per_page

    versions =
      Sheets.list_versions(
        socket.assigns.sheet.id,
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

  defp notify_parent(:saved) do
    send(self(), {:versions_section, :saved})
  end

  defp notify_parent(:sheet_updated, sheet) do
    send(self(), {:versions_section, :sheet_updated, sheet})
  end

  defp notify_parent(:version_restored, data) do
    send(self(), {:versions_section, :version_restored, data})
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
      <p class="text-base-content/70 mb-2">{dgettext("sheets", "No versions yet")}</p>
      <p class="text-sm text-base-content/50">
        {dgettext("sheets", "Create a version to save the current state of this sheet.")}
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
            {@version.title || @version.change_summary || dgettext("sheets", "No summary")}
          </span>
          <span :if={@is_current} class="badge badge-primary badge-sm">
            {dgettext("sheets", "Current")}
          </span>
        </div>
        <p :if={@version.description} class="text-sm text-base-content/70 mt-0.5">
          {@version.description}
        </p>
        <div class="flex items-center gap-2 text-xs text-base-content/60 mt-0.5">
          <span>{format_version_date(@version.inserted_at)}</span>
          <span :if={@version.changed_by}>
            · {dgettext("sheets", "by")} {@version.changed_by.display_name ||
              @version.changed_by.email}
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
          data-tip={dgettext("sheets", "Restore this version")}
          phx-click="restore_version"
          phx-value-version={@version.version_number}
          phx-target={@target}
        >
          <.icon name="rotate-ccw" class="size-4" />
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs tooltip text-error"
          data-tip={dgettext("sheets", "Delete version")}
          phx-click={
            JS.push("set_pending_delete_version",
              value: %{version: @version.version_number},
              target: @target
            )
            |> show_modal("delete-version-confirm")
          }
        >
          <.icon name="trash-2" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  attr :target, :any, default: nil

  defp create_version_modal(assigns) do
    ~H"""
    <dialog
      id="create-version-modal"
      class="modal modal-open"
      phx-click-away="hide_create_version_modal"
      phx-target={@target}
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">{dgettext("sheets", "Create Version")}</h3>
        <form phx-submit="create_version" phx-target={@target}>
          <div class="mb-4">
            <label class="label" for="version-title">
              <span class="label-text">{dgettext("sheets", "Title")}</span>
            </label>
            <input
              type="text"
              name="title"
              id="version-title"
              class="input input-bordered w-full"
              placeholder={dgettext("sheets", "e.g., Before major refactor")}
              autofocus
            />
          </div>
          <div class="mb-4">
            <label class="label" for="version-description">
              <span class="label-text">
                {dgettext("sheets", "Description")} ({dgettext("sheets", "optional")})
              </span>
            </label>
            <textarea
              name="description"
              id="version-description"
              class="textarea textarea-bordered w-full"
              rows="3"
              placeholder={dgettext("sheets", "Describe what this version captures...")}
            ></textarea>
          </div>
          <div class="modal-action">
            <button
              type="button"
              class="btn btn-ghost"
              phx-click="hide_create_version_modal"
              phx-target={@target}
            >
              {dgettext("sheets", "Cancel")}
            </button>
            <button type="submit" class="btn btn-primary">
              <.icon name="save" class="size-4" />
              {dgettext("sheets", "Create Version")}
            </button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button type="button" phx-click="hide_create_version_modal" phx-target={@target}>
          close
        </button>
      </form>
    </dialog>
    """
  end

  defp format_version_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end
end
