defmodule StoryarnWeb.PageLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  alias Storyarn.Pages
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
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      selected_page_id={to_string(@page.id)}
      can_edit={@can_edit}
    >
      <%!-- Breadcrumb --%>
      <nav class="text-sm mb-4">
        <ol class="flex items-center gap-1 text-base-content/70">
          <li :for={{ancestor, idx} <- Enum.with_index(@ancestors)}>
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{ancestor.id}"
              }
              class="hover:text-primary flex items-center gap-1"
            >
              <.page_icon icon={ancestor.icon} size="sm" />
              {ancestor.name}
            </.link>
            <span :if={idx < length(@ancestors) - 1} class="mx-1 text-base-content/50">/</span>
          </li>
        </ol>
      </nav>

      <%!-- Page Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <.page_icon icon={@page.icon} size="xl" />
            <div class="flex-1">
              <h1
                :if={!@editing_name}
                class="text-3xl font-bold cursor-pointer hover:bg-base-200 rounded px-2 -mx-2 py-1"
                phx-click="edit_name"
              >
                {@page.name}
              </h1>
              <form :if={@editing_name} phx-submit="save_name" phx-click-away="cancel_edit_name">
                <input
                  type="text"
                  name="name"
                  value={@page.name}
                  class="input input-bordered text-3xl font-bold w-full"
                  autofocus
                  phx-key="escape"
                  phx-keydown="cancel_edit_name"
                />
              </form>
            </div>
          </div>
        </div>
        <%!-- Save indicator (positioned at header level) --%>
        <.save_indicator status={@save_status} />
      </div>

      <div class="max-w-3xl mx-auto">
        <%!-- Blocks --%>
        <div
          id="blocks-container"
          class="space-y-2 min-h-[200px]"
          phx-hook={if @can_edit, do: "SortableList", else: nil}
          data-group="blocks"
          data-handle=".drag-handle"
        >
          <div
            :for={block <- @blocks}
            class="group relative"
            id={"block-#{block.id}"}
            data-id={block.id}
          >
            <.block_component
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
            />
          </div>

          <%!-- Add block button / slash command --%>
          <div :if={@can_edit} class="relative">
            <div
              :if={!@show_block_menu}
              class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
              phx-click="show_block_menu"
            >
              <.icon name="hero-plus" class="size-4 opacity-0 group-hover:opacity-100" />
              <span class="text-sm">{gettext("Type / to add a block")}</span>
            </div>

            <.block_menu :if={@show_block_menu} />
          </div>
        </div>

        <%!-- Children pages --%>
        <div :if={@children != []} class="mt-12 pt-8 border-t border-base-300">
          <h2 class="text-lg font-semibold mb-4">{gettext("Subpages")}</h2>
          <div class="space-y-2">
            <.link
              :for={child <- @children}
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{child.id}"
              }
              class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
            >
              <.page_icon icon={child.icon} size="md" />
              <span>{child.name}</span>
            </.link>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :editing_block_id, :any, default: nil

  defp block_component(assigns) do
    is_editing = assigns.editing_block_id == assigns.block.id
    assigns = assign(assigns, :is_editing, is_editing)

    ~H"""
    <div class="flex items-start gap-2">
      <%!-- Drag handle and menu --%>
      <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 pt-2">
        <button
          :if={@can_edit}
          type="button"
          class="drag-handle btn btn-ghost btn-xs cursor-grab active:cursor-grabbing"
          title={gettext("Drag to reorder")}
        >
          <.icon name="hero-bars-2" class="size-3" />
        </button>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="delete_block"
          phx-value-id={@block.id}
        >
          <.icon name="hero-trash" class="size-3" />
        </button>
      </div>

      <%!-- Block content --%>
      <div class="flex-1">
        <%= case @block.type do %>
          <% "text" -> %>
            <.text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "rich_text" -> %>
            <.rich_text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "number" -> %>
            <.number_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "select" -> %>
            <.select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "multi_select" -> %>
            <.multi_select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% _ -> %>
            <div class="text-base-content/50">{gettext("Unknown block type")}</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div>
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="text"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class="py-2">{@content}</div>
    </div>
    """
  end

  defp rich_text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)

    ~H"""
    <div>
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <div
        id={"tiptap-#{@block.id}"}
        phx-hook="TiptapEditor"
        phx-update="ignore"
        data-content={@content}
        data-editable={to_string(@can_edit)}
        data-block-id={@block.id}
      >
      </div>
    </div>
    """
  end

  defp number_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || "0"
    content = get_in(assigns.block.value, ["content"])

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div>
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="number"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class="py-2">{@content || "-"}</div>
    </div>
    """
  end

  defp select_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || gettext("Select...")
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"])

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:options, options)
      |> assign(:content, content)

    ~H"""
    <div>
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <select
        :if={@can_edit}
        class="select select-bordered w-full"
        phx-change="update_block_value"
        phx-value-id={@block.id}
      >
        <option value="">{@placeholder}</option>
        <option
          :for={opt <- @options}
          value={opt["key"]}
          selected={@content == opt["key"]}
        >
          {opt["value"]}
        </option>
      </select>
      <div :if={!@can_edit} class="py-2">
        {find_option_label(@options, @content) || "-"}
      </div>
    </div>
    """
  end

  defp multi_select_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"]) || []

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:options, options)
      |> assign(:content, content)

    ~H"""
    <div>
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <div :if={@can_edit} class="flex flex-wrap gap-2">
        <label :for={opt <- @options} class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            value={opt["key"]}
            checked={opt["key"] in @content}
            phx-click="toggle_multi_select"
            phx-value-id={@block.id}
            phx-value-key={opt["key"]}
          />
          <span class="text-sm">{opt["value"]}</span>
        </label>
      </div>
      <div :if={!@can_edit} class="flex flex-wrap gap-1 py-2">
        <span
          :for={key <- @content}
          class="badge badge-sm"
        >
          {find_option_label(@options, key)}
        </span>
        <span :if={@content == []} class="text-base-content/50">-</span>
      </div>
    </div>
    """
  end

  defp find_option_label(options, key) do
    Enum.find_value(options, fn opt -> opt["key"] == key && opt["value"] end)
  end

  defp block_menu(assigns) do
    ~H"""
    <div class="absolute z-10 bg-base-100 border border-base-300 rounded-lg shadow-lg p-2 w-64">
      <div class="text-xs text-base-content/50 px-2 py-1 uppercase">{gettext("Basic Blocks")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="rich_text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Rich Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="number"
      >
        <span class="text-lg">#</span>
        <span>{gettext("Number")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="select"
      >
        <.icon name="hero-chevron-down" class="size-4" />
        <span>{gettext("Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="multi_select"
      >
        <.icon name="hero-check" class="size-4" />
        <span>{gettext("Multi Select")}</span>
      </button>

      <div class="border-t border-base-300 mt-2 pt-2">
        <button
          type="button"
          class="w-full text-left px-2 py-1 text-sm text-base-content/50 hover:text-base-content"
          phx-click="hide_block_menu"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end

  @page_icon_sizes %{
    "sm" => {"size-4", "text-sm"},
    "md" => {"size-5", "text-base"},
    "lg" => {"size-6", "text-lg"},
    "xl" => {"size-10", "text-5xl"}
  }

  attr :icon, :string, default: nil
  attr :size, :string, values: ["sm", "md", "lg", "xl"], default: "md"

  defp page_icon(assigns) do
    {size_class, text_size} = Map.get(@page_icon_sizes, assigns.size, {"size-5", "text-base"})
    is_emoji = assigns.icon && assigns.icon not in [nil, "", "page"]

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:text_size, text_size)
      |> assign(:is_emoji, is_emoji)

    ~H"""
    <span :if={@is_emoji} class={@text_size}>{@icon}</span>
    <.icon :if={!@is_emoji} name="hero-document" class={"#{@size_class} opacity-60"} />
    """
  end

  attr :status, :atom, required: true

  defp save_indicator(assigns) do
    ~H"""
    <div
      :if={@status != :idle}
      class="absolute top-2 right-0 z-10 animate-in fade-in duration-300"
    >
      <div class={[
        "flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium",
        @status == :saving && "bg-base-200 text-base-content",
        @status == :saved && "bg-success/10 text-success"
      ]}>
        <span :if={@status == :saving} class="loading loading-spinner loading-xs"></span>
        <.icon :if={@status == :saved} name="hero-check" class="size-4" />
        <span :if={@status == :saving}>{gettext("Saving...")}</span>
        <span :if={@status == :saved}>{gettext("Saved")}</span>
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => page_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        case Pages.get_page(project.id, page_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Page not found."))
             |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/pages")}

          page ->
            project = Repo.preload(project, :workspace)
            pages_tree = Pages.list_pages_tree(project.id)
            ancestors = Pages.get_page_with_ancestors(project.id, page_id) || [page]
            children = Pages.get_children(page.id)
            blocks = Pages.list_blocks(page.id)
            can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:workspace, project.workspace)
              |> assign(:membership, membership)
              |> assign(:page, page)
              |> assign(:pages_tree, pages_tree)
              |> assign(:ancestors, ancestors)
              |> assign(:children, children)
              |> assign(:blocks, blocks)
              |> assign(:can_edit, can_edit)
              |> assign(:editing_name, false)
              |> assign(:editing_block_id, nil)
              |> assign(:show_block_menu, false)
              |> assign(:save_status, :idle)

            {:ok, socket}
        end

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

  @impl true
  def handle_event("edit_name", _params, socket) do
    if socket.assigns.can_edit do
      {:noreply, assign(socket, :editing_name, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.update_page(socket.assigns.page, %{name: name}) do
          {:ok, page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:page, page)
             |> assign(:pages_tree, pages_tree)
             |> assign(:editing_name, false)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_name, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_page", %{"id" => page_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        page = Pages.get_page!(socket.assigns.project.id, page_id)
        do_delete_page(socket, page)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  def handle_event("add_block", %{"type" => type}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.create_block(socket.assigns.page, %{type: type}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:show_block_menu, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not add block."))
             |> assign(:show_block_menu, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => value}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)
        current = get_in(block.value, ["content"]) || []

        new_content =
          if key in current do
            List.delete(current, key)
          else
            [key | current]
          end

        case Pages.update_block_value(block, %{"content" => new_content}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.delete_block(block) do
          {:ok, _} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            {:noreply, assign(socket, :blocks, blocks)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => content}) do
          {:ok, _block} ->
            # Don't reload blocks to avoid disrupting the editor
            schedule_save_status_reset()
            {:noreply, assign(socket, :save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.reorder_blocks(socket.assigns.page.id, ids) do
          {:ok, blocks} ->
            {:noreply, assign(socket, :blocks, blocks)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_page",
        %{"page_id" => page_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        page = Pages.get_page!(socket.assigns.project.id, page_id)
        parent_id = normalize_parent_id(parent_id)

        case Pages.move_page_to_position(page, parent_id, position) do
          {:ok, _page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
            {:noreply, assign(socket, :pages_tree, pages_tree)}

          {:error, :would_create_cycle} ->
            {:noreply,
             put_flash(socket, :error, gettext("Cannot move a page into its own children."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not move page."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_page", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{name: gettext("New Page"), parent_id: parent_id}

        case Pages.create_page(socket.assigns.project, attrs) do
          {:ok, new_page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:pages_tree, pages_tree)
             |> push_navigate(
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 4000)
  end

  defp do_delete_page(socket, page) do
    case Pages.delete_page(page) do
      {:ok, _} ->
        handle_page_deleted(socket, page)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete page."))}
    end
  end

  defp handle_page_deleted(socket, deleted_page) do
    socket = put_flash(socket, :info, gettext("Page deleted successfully."))

    if deleted_page.id == socket.assigns.page.id do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages"
       )}
    else
      pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
      {:noreply, assign(socket, :pages_tree, pages_tree)}
    end
  end

  defp normalize_parent_id(""), do: nil
  defp normalize_parent_id(nil), do: nil
  defp normalize_parent_id(parent_id), do: parent_id
end
