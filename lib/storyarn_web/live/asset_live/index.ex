defmodule StoryarnWeb.AssetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.AssetLive.Components.AssetComponents

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
          {dgettext("assets", "Assets")}
          <:subtitle>
            {dgettext("assets", "Manage images, audio, and other files for your project")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <label class={["btn btn-primary", @uploading && "btn-disabled"]}>
              <.icon name="upload" class="size-4 mr-2" />
              {if @uploading, do: dgettext("assets", "Uploading..."), else: dgettext("assets", "Upload")}
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
                placeholder={dgettext("assets", "Search files...")}
                phx-debounce="300"
                class="grow"
              />
            </label>
          </form>
        </div>

        <.empty_state :if={@assets == []} icon="image">
          {dgettext("assets", "No assets yet. Upload files to get started.")}
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
          title={dgettext("assets", "Delete asset?")}
          message={delete_confirm_message(@asset_usages)}
          confirm_text={dgettext("assets", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete_asset")}
        />
      </div>
    </Layouts.project>
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
         |> put_flash(:error, dgettext("assets", "You don't have access to this project."))
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
         put_flash(socket, :error, dgettext("assets", "You don't have permission to delete assets."))}
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
         |> put_flash(:error, dgettext("assets", "You don't have permission to upload files."))}
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
         |> put_flash(:error, dgettext("assets", "Invalid file data."))}
    end
  end

  defp do_upload(socket, filename, content_type, binary_data) do
    if Asset.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      safe_filename = Assets.sanitize_filename(filename)
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
         |> put_flash(:info, dgettext("assets", "Asset uploaded successfully."))}
      else
        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:uploading, false)
           |> put_flash(:error, upload_error_message(reason))}
      end
    else
      {:noreply,
       socket
       |> assign(:uploading, false)
       |> put_flash(:error, dgettext("assets", "Unsupported file type."))}
    end
  end

  defp upload_error_message(%Ecto.Changeset{}), do: dgettext("assets", "Could not save asset.")
  defp upload_error_message(_), do: dgettext("assets", "Upload failed. Please try again.")

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
             |> put_flash(:info, dgettext("assets", "Asset deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("assets", "Could not delete asset."))}
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
      {"all", dgettext("assets", "All"), total},
      {"image", dgettext("assets", "Images"), image_count},
      {"audio", dgettext("assets", "Audio"), audio_count}
    ]
  end

  defp delete_confirm_message(usages) do
    total =
      length(usages.flow_nodes) + length(usages.sheet_avatars) + length(usages.sheet_banners)

    if total > 0 do
      dngettext(
        "assets",
        "This asset is used in %{count} place. Are you sure you want to delete it?",
        "This asset is used in %{count} places. Are you sure you want to delete it?",
        total,
        count: total
      )
    else
      dgettext("assets", "Are you sure you want to delete this asset? This cannot be undone.")
    end
  end
end
