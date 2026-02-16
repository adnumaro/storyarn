defmodule StoryarnWeb.AssetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/assets"}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {gettext("Assets")}
          <:subtitle>
            {gettext("Manage images, audio, and other files for your project")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <label class={["btn btn-primary", @uploading && "btn-disabled"]}>
              <.icon name="upload" class="size-4 mr-2" />
              {if @uploading, do: gettext("Uploading..."), else: gettext("Upload")}
              <input
                type="file"
                accept="image/*,audio/*"
                class="hidden"
                phx-hook="AssetUpload"
                id="asset-upload-input"
              />
            </label>
          </:actions>
        </.header>

        <%!-- Filter tabs + Search --%>
        <div class="flex items-center justify-between mt-6 mb-4 gap-4">
          <div role="tablist" class="tabs tabs-border">
            <button
              :for={{type, label, count} <- filter_tabs(@type_counts)}
              role="tab"
              class={["tab", @filter == type && "tab-active"]}
              phx-click="filter_assets"
              phx-value-type={type}
            >
              {label}
              <span class="badge badge-sm ml-1">{count}</span>
            </button>
          </div>

          <form phx-change="search_assets" class="flex-shrink-0">
            <label class="input input-sm input-bordered flex items-center gap-2">
              <.icon name="search" class="size-4 opacity-50" />
              <input
                type="text"
                name="search"
                value={@search}
                placeholder={gettext("Search files...")}
                phx-debounce="300"
                class="grow"
              />
            </label>
          </form>
        </div>

        <.empty_state :if={@assets == []} icon="image">
          {gettext("No assets yet. Upload files to get started.")}
        </.empty_state>

        <%!-- Asset grid + detail panel --%>
        <div :if={@assets != []} class="flex gap-6">
          <div class={[
            "grid gap-4 flex-1",
            @selected_asset && "grid-cols-2 sm:grid-cols-2",
            !@selected_asset && "grid-cols-2 sm:grid-cols-3 md:grid-cols-4"
          ]}>
            <.asset_card
              :for={asset <- @assets}
              asset={asset}
              selected={@selected_asset && @selected_asset.id == asset.id}
            />
          </div>

          <.detail_panel
            :if={@selected_asset}
            asset={@selected_asset}
            usages={@asset_usages}
            workspace={@workspace}
            project={@project}
            can_edit={@can_edit}
          />
        </div>

        <.confirm_modal
          :if={@can_edit}
          id="delete-asset-confirm"
          title={gettext("Delete asset?")}
          message={delete_confirm_message(@asset_usages)}
          confirm_text={gettext("Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete_asset")}
        />
      </div>
    </Layouts.project>
    """
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  attr :asset, :map, required: true
  attr :selected, :boolean, default: false

  defp asset_card(assigns) do
    ~H"""
    <div
      class={[
        "card bg-base-100 border shadow-sm hover:shadow-md transition-shadow cursor-pointer overflow-hidden",
        @selected && "border-primary ring-2 ring-primary/20",
        !@selected && "border-base-300"
      ]}
      phx-click="select_asset"
      phx-value-id={@asset.id}
    >
      <%!-- Thumbnail area --%>
      <figure class="h-32 bg-base-200 flex items-center justify-center">
        <img
          :if={Asset.image?(@asset)}
          src={@asset.url}
          alt={@asset.filename}
          class="w-full h-full object-cover"
        />
        <div :if={Asset.audio?(@asset)} class="text-center">
          <.icon name="music" class="size-10 text-base-content/30" />
        </div>
        <div :if={!Asset.image?(@asset) and !Asset.audio?(@asset)} class="text-center">
          <.icon name="file" class="size-10 text-base-content/30" />
        </div>
      </figure>

      <%!-- Info --%>
      <div class="card-body p-3">
        <p class="text-sm font-medium truncate" title={@asset.filename}>{@asset.filename}</p>
        <div class="flex items-center justify-between text-xs text-base-content/60">
          <span>{format_size(@asset.size)}</span>
          <span class={["badge badge-xs", type_badge_class(@asset)]}>{type_label(@asset)}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :asset, :map, required: true
  attr :usages, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, default: false

  defp detail_panel(assigns) do
    total_usages =
      length(assigns.usages.flow_nodes) +
        length(assigns.usages.sheet_avatars) +
        length(assigns.usages.sheet_banners)

    assigns = assign(assigns, :total_usages, total_usages)

    ~H"""
    <div class="w-80 flex-shrink-0 border border-base-300 rounded-lg bg-base-100 p-4 space-y-4 self-start">
      <%!-- Close button --%>
      <div class="flex items-center justify-between">
        <h3 class="font-semibold text-sm">{gettext("Details")}</h3>
        <button type="button" phx-click="deselect_asset" class="btn btn-ghost btn-xs btn-square">
          <.icon name="x" class="size-4" />
        </button>
      </div>

      <%!-- Preview --%>
      <div class="rounded-lg overflow-hidden bg-base-200">
        <img
          :if={Asset.image?(@asset)}
          src={@asset.url}
          alt={@asset.filename}
          class="w-full object-contain max-h-48"
        />
        <div :if={Asset.audio?(@asset)} class="p-4">
          <audio controls class="w-full">
            <source src={@asset.url} type={@asset.content_type} />
          </audio>
        </div>
        <div
          :if={!Asset.image?(@asset) and !Asset.audio?(@asset)}
          class="p-6 flex items-center justify-center"
        >
          <.icon name="file" class="size-12 text-base-content/30" />
        </div>
      </div>

      <%!-- Metadata --%>
      <dl class="text-sm space-y-2">
        <div>
          <dt class="text-base-content/50">{gettext("Filename")}</dt>
          <dd class="font-medium break-all">{@asset.filename}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{gettext("Type")}</dt>
          <dd>{@asset.content_type}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{gettext("Size")}</dt>
          <dd>{format_size(@asset.size)}</dd>
        </div>
        <div>
          <dt class="text-base-content/50">{gettext("Uploaded")}</dt>
          <dd>{Calendar.strftime(@asset.inserted_at, "%b %d, %Y")}</dd>
        </div>
      </dl>

      <%!-- Usage section --%>
      <div class="border-t border-base-300 pt-4">
        <h4 class="text-sm font-medium mb-2 flex items-center gap-2">
          <.icon name="link" class="size-4" />
          {gettext("Usage")}
          <span class="badge badge-xs">{@total_usages}</span>
        </h4>

        <div :if={@total_usages == 0} class="text-sm text-base-content/50">
          {gettext("Not used anywhere")}
        </div>

        <ul :if={@total_usages > 0} class="text-sm space-y-1">
          <li :for={usage <- @usages.flow_nodes} class="flex items-center gap-2">
            <.icon name="git-branch" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{usage.flow_id}"
              }
              class="text-primary hover:underline truncate"
            >
              {usage.flow_name}
            </.link>
          </li>
          <li :for={sheet <- @usages.sheet_avatars} class="flex items-center gap-2">
            <.icon name="user" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{sheet.id}"
              }
              class="text-primary hover:underline truncate"
            >
              {sheet.name}
              <span class="text-base-content/40">({gettext("avatar")})</span>
            </.link>
          </li>
          <li :for={sheet <- @usages.sheet_banners} class="flex items-center gap-2">
            <.icon name="image" class="size-3 text-base-content/50" />
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{sheet.id}"
              }
              class="text-primary hover:underline truncate"
            >
              {sheet.name}
              <span class="text-base-content/40">({gettext("banner")})</span>
            </.link>
          </li>
        </ul>
      </div>

      <%!-- Delete button --%>
      <div :if={@can_edit} class="border-t border-base-300 pt-4">
        <button
          type="button"
          class="btn btn-error btn-sm btn-outline w-full"
          phx-click={show_modal("delete-asset-confirm")}
        >
          <.icon name="trash-2" class="size-4" />
          {gettext("Delete asset")}
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Lifecycle
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
        project = Repo.preload(project, :workspace)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
        type_counts = Assets.count_assets_by_type(project.id)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:filter, "all")
          |> assign(:search, "")
          |> assign(:type_counts, type_counts)
          |> assign(:selected_asset, nil)
          |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})
          |> assign(:uploading, false)
          |> load_assets()

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("filter_assets", %{"type" => type}, socket)
      when type in ["all", "image", "audio"] do
    {:noreply,
     socket
     |> assign(:filter, type)
     |> load_assets()}
  end

  def handle_event("search_assets", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> load_assets()}
  end

  def handle_event("select_asset", %{"id" => id}, socket) do
    project_id = socket.assigns.project.id

    case Assets.get_asset(project_id, String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      asset ->
        usages = Assets.get_asset_usages(project_id, asset.id)

        {:noreply,
         socket
         |> assign(:selected_asset, asset)
         |> assign(:asset_usages, usages)}
    end
  end

  def handle_event("deselect_asset", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_asset, nil)
     |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})}
  end

  def handle_event("confirm_delete_asset", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        delete_selected_asset(socket)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to delete assets."))}
    end
  end

  def handle_event("upload_started", _params, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  def handle_event("upload_validation_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(:uploading, false)
     |> put_flash(:error, message)}
  end

  def handle_event(
        "upload_asset",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        process_upload(socket, filename, content_type, data)

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, gettext("You don't have permission to upload files."))}
    end
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp process_upload(socket, filename, content_type, data) do
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        do_upload(socket, filename, content_type, binary_data)

      :error ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, gettext("Invalid file data."))}
    end
  end

  defp do_upload(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user
    safe_filename = sanitize_filename(filename)
    key = Assets.generate_key(project, safe_filename)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key
    }

    with {:ok, url} <- Storage.upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)) do
      type_counts = Assets.count_assets_by_type(project.id)
      usages = Assets.get_asset_usages(project.id, asset.id)

      {:noreply,
       socket
       |> assign(:uploading, false)
       |> assign(:type_counts, type_counts)
       |> assign(:selected_asset, asset)
       |> assign(:asset_usages, usages)
       |> load_assets()
       |> put_flash(:info, gettext("Asset uploaded successfully."))}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, upload_error_message(reason))}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.downcase()
  end

  defp upload_error_message(%Ecto.Changeset{}), do: gettext("Could not save asset.")
  defp upload_error_message(_), do: gettext("Upload failed. Please try again.")

  defp delete_selected_asset(socket) do
    case socket.assigns.selected_asset do
      nil ->
        {:noreply, socket}

      asset ->
        # Delete from storage (best-effort)
        Storage.delete(asset.key)

        if thumbnail_key = asset.metadata["thumbnail_key"] do
          Storage.delete(thumbnail_key)
        end

        case Assets.delete_asset(asset) do
          {:ok, _} ->
            type_counts = Assets.count_assets_by_type(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:selected_asset, nil)
             |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})
             |> assign(:type_counts, type_counts)
             |> load_assets()
             |> put_flash(:info, gettext("Asset deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete asset."))}
        end
    end
  end

  defp load_assets(socket) do
    project_id = socket.assigns.project.id
    opts = filter_opts(socket.assigns.filter) ++ search_opts(socket.assigns.search)
    assign(socket, :assets, Assets.list_assets(project_id, opts))
  end

  defp filter_opts("all"), do: []
  defp filter_opts("image"), do: [content_type: "image/"]
  defp filter_opts("audio"), do: [content_type: "audio/"]

  defp search_opts(""), do: []
  defp search_opts(term), do: [search: term]

  # ===========================================================================
  # Private: View Helpers
  # ===========================================================================

  defp filter_tabs(type_counts) do
    total = type_counts |> Map.values() |> Enum.sum()
    image_count = Map.get(type_counts, "image", 0)
    audio_count = Map.get(type_counts, "audio", 0)

    [
      {"all", gettext("All"), total},
      {"image", gettext("Images"), image_count},
      {"audio", gettext("Audio"), audio_count}
    ]
  end

  defp format_size(nil), do: ""

  defp format_size(bytes) when bytes < 1_024,
    do: "#{bytes} B"

  defp format_size(bytes) when bytes < 1_048_576,
    do: "#{Float.round(bytes / 1_024, 1)} KB"

  defp format_size(bytes),
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp type_label(%Asset{} = asset) do
    cond do
      Asset.image?(asset) -> gettext("Image")
      Asset.audio?(asset) -> gettext("Audio")
      true -> gettext("File")
    end
  end

  defp delete_confirm_message(usages) do
    total =
      length(usages.flow_nodes) + length(usages.sheet_avatars) + length(usages.sheet_banners)

    if total > 0 do
      ngettext(
        "This asset is used in %{count} place. Are you sure you want to delete it?",
        "This asset is used in %{count} places. Are you sure you want to delete it?",
        total,
        count: total
      )
    else
      gettext("Are you sure you want to delete this asset? This cannot be undone.")
    end
  end

  defp type_badge_class(%Asset{} = asset) do
    cond do
      Asset.image?(asset) -> "badge-primary"
      Asset.audio?(asset) -> "badge-secondary"
      true -> "badge-ghost"
    end
  end
end
