defmodule StoryarnWeb.SheetLive.Components.ContentTab do
  @moduledoc """
  LiveComponent for the Content tab in the sheet editor.
  Handles all block-related events: add, update, delete, reorder, configure.
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.BlockComponents
  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.BlockHelpers
  alias StoryarnWeb.SheetLive.Helpers.ConfigHelpers
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- Inherited Properties (grouped by source sheet) --%>
      <div :for={group <- @inherited_groups} class="mb-6">
        <.inherited_section_header
          source_sheet={group.source_sheet}
          block_count={length(group.blocks)}
          workspace={@workspace}
          project={@project}
        />
        <div class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16 border-l-2 border-info/30 ml-1">
          <div
            :for={block <- group.blocks}
            class="group relative w-full px-2 sm:px-8 md:px-16"
            id={"block-#{block.id}"}
          >
            <.inherited_block_wrapper
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
              target={@myself}
            />
          </div>
        </div>
      </div>

      <%!-- Own Properties --%>
      <div
        :if={@inherited_groups != []}
        class="text-xs text-base-content/50 uppercase tracking-wider mt-6 mb-2 px-2 sm:px-8 md:px-16"
      >
        {gettext("Own Properties")}
      </div>

      <div
        id="blocks-container"
        class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16"
        phx-hook={if @can_edit, do: "SortableList", else: nil}
        phx-target={@myself}
        data-phx-target={"##{@id}"}
        data-group="blocks"
        data-handle=".drag-handle"
      >
        <div
          :for={block <- @own_blocks}
          class="group relative w-full px-2 sm:px-8 md:px-16"
          id={"block-#{block.id}"}
          data-id={block.id}
        >
          <.block_component
            block={block}
            can_edit={@can_edit}
            editing_block_id={@editing_block_id}
            target={@myself}
          />
        </div>
      </div>

      <%!-- Add block button / slash command --%>
      <div :if={@can_edit} class="relative mt-2">
        <div
          :if={!@show_block_menu}
          class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
          phx-click="show_block_menu"
          phx-target={@myself}
        >
          <.icon name="plus" class="size-4 opacity-0 group-hover:opacity-100" />
          <span class="text-sm">{gettext("Type / to add a block")}</span>
        </div>

        <.block_menu :if={@show_block_menu} target={@myself} scope={@block_scope} />
      </div>

      <%!-- Children sheets --%>
      <.children_sheets_section
        :if={@children != []}
        children={@children}
        workspace={@workspace}
        project={@project}
      />

      <%!-- Configuration Panel (Right Sidebar) --%>
      <.config_panel :if={@configuring_block} block={@configuring_block} target={@myself} />

      <%!-- Propagation Modal --%>
      <.live_component
        :if={@propagation_block}
        module={StoryarnWeb.SheetLive.Components.PropagationModal}
        id="propagation-modal"
        block={@propagation_block}
        sheet={@sheet}
        target={@myself}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_block_menu, fn -> false end)
      |> assign_new(:editing_block_id, fn -> nil end)
      |> assign_new(:configuring_block, fn -> nil end)
      |> assign_new(:block_scope, fn -> "self" end)
      |> assign_new(:propagation_block, fn -> nil end)

    # Split blocks into inherited and own groups using optimized batch query
    {inherited_groups, own_blocks} =
      Sheets.get_sheet_blocks_grouped(socket.assigns.sheet.id)

    # Enrich blocks with reference_target for reference-type blocks
    project_id = socket.assigns.project.id

    inherited_groups =
      Enum.map(inherited_groups, fn group ->
        %{group | blocks: enrich_with_references(group.blocks, project_id)}
      end)

    own_blocks = enrich_with_references(own_blocks, project_id)

    socket =
      socket
      |> assign(:inherited_groups, inherited_groups)
      |> assign(:own_blocks, own_blocks)

    {:ok, socket}
  end

  # ===========================================================================
  # Block Menu Events
  # ===========================================================================

  @impl true
  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  # ===========================================================================
  # Block Scope Events
  # ===========================================================================

  def handle_event("set_block_scope", %{"scope" => scope}, socket)
      when scope in ["self", "children"] do
    {:noreply, assign(socket, :block_scope, scope)}
  end

  # ===========================================================================
  # Block CRUD Events
  # ===========================================================================

  def handle_event("add_block", %{"type" => type}, socket) do
    with_authorization(socket, fn socket ->
      sheet = socket.assigns.sheet
      scope = socket.assigns.block_scope

      case Sheets.create_block(sheet, %{type: type, scope: scope}) do
        {:ok, _block} ->
          socket =
            socket
            |> assign(:show_block_menu, false)
            |> assign(:block_scope, "self")

          # If scope is "children" and sheet already has descendants that weren't
          # auto-propagated (e.g., if we want the propagation modal), it's already
          # handled by BlockCrud.create_block. No modal needed for new blocks since
          # they auto-propagate to all descendants.
          notify_parent(socket, :saved)
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create block."))}
      end
    end)
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      # Wrap raw value in %{"content" => value} structure expected by the schema
      case Sheets.update_block_value(block, %{"content" => value}) do
        {:ok, _updated} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update block."))}
      end
    end)
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      case Sheets.delete_block(block) do
        {:ok, _} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
      end
    end)
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    with_authorization(socket, fn socket ->
      sheet_id = socket.assigns.sheet.id
      block_ids = Enum.map(ids, &to_integer/1)

      case Sheets.reorder_blocks(sheet_id, block_ids) do
        {:ok, _} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
      end
    end)
  end

  # ===========================================================================
  # Multi-Select Events
  # ===========================================================================

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.toggle_multi_select_value(socket, block_id, key)
      handle_block_result(socket, result)
    end)
  end

  def handle_event(
        "multi_select_keydown",
        %{"key" => "Enter", "value" => value, "id" => block_id},
        socket
      ) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.handle_multi_select_enter_value(socket, block_id, value)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Rich Text Events
  # ===========================================================================

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.update_rich_text_value(socket, block_id, content)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("mention_suggestions", %{"query" => query}, socket)
      when is_binary(query) and byte_size(query) <= 100 do
    project_id = socket.assigns.project.id
    results = Sheets.search_referenceable(project_id, query, ["sheet", "flow"])

    items =
      Enum.map(results, fn result ->
        %{
          id: result.id,
          type: result.type,
          name: result.name,
          shortcut: result.shortcut,
          label: result.shortcut || result.name
        }
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
  end

  def handle_event("mention_suggestions", _params, socket) do
    {:noreply, push_event(socket, "mention_suggestions_result", %{items: []})}
  end

  # ===========================================================================
  # Boolean Block Events
  # ===========================================================================

  def handle_event("set_boolean_block", %{"id" => block_id, "value" => value}, socket) do
    with_authorization(socket, fn socket ->
      result = BlockHelpers.set_boolean_block_value(socket, block_id, value)
      handle_block_result(socket, result)
    end)
  end

  # ===========================================================================
  # Configuration Panel Events
  # ===========================================================================

  def handle_event("configure_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)
      {:noreply, assign(socket, :configuring_block, block)}
    end)
  end

  def handle_event("close_config_panel", _params, socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block

      case Sheets.update_block_config(block, config_params) do
        {:ok, updated_block} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:configuring_block, updated_block)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not save configuration."))}
      end
    end)
  end

  def handle_event("toggle_constant", _params, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block
      new_value = !block.is_constant

      case Sheets.update_block(block, %{is_constant: new_value}) do
        {:ok, updated_block} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:configuring_block, updated_block)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not toggle constant."))}
      end
    end)
  end

  # ===========================================================================
  # Select Options Events
  # ===========================================================================

  def handle_event("add_select_option", _params, socket) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.add_select_option(socket)
    end)
  end

  def handle_event("remove_select_option", %{"index" => index}, socket) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.remove_select_option(socket, index)
    end)
  end

  def handle_event(
        "update_select_option",
        %{"index" => index, "key" => key, "value" => value},
        socket
      ) do
    with_authorization(socket, fn socket ->
      ConfigHelpers.update_select_option(socket, index, key, value)
    end)
  end

  # ===========================================================================
  # Reference Block Events
  # ===========================================================================

  def handle_event("search_references", %{"value" => query, "block-id" => block_id}, socket) do
    ReferenceHelpers.search_references(socket, query, block_id)
  end

  def handle_event(
        "select_reference",
        %{"block-id" => block_id, "type" => target_type, "id" => target_id},
        socket
      ) do
    with_authorization(socket, fn socket ->
      result = ReferenceHelpers.select_reference_value(socket, block_id, target_type, target_id)
      handle_block_result(socket, result)
    end)
  end

  def handle_event("clear_reference", %{"block-id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      result = ReferenceHelpers.clear_reference_value(socket, block_id)
      handle_block_result(socket, result)
    end)
  end

  # ===========================================================================
  # Inheritance Action Events
  # ===========================================================================

  def handle_event("detach_inherited_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      case Sheets.detach_block(block) do
        {:ok, _} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Property detached. Changes to the source won't affect this copy."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not detach property."))}
      end
    end)
  end

  def handle_event("reattach_block", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      project_id = socket.assigns.project.id
      block = Sheets.get_block_in_project!(block_id, project_id)

      case Sheets.reattach_block(block) do
        {:ok, _} ->
          maybe_create_version(socket)
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:configuring_block, nil)
           |> put_flash(:info, gettext("Property re-synced with source."))}

        {:error, :source_not_found} ->
          {:noreply, put_flash(socket, :error, gettext("Source block no longer exists."))}
      end
    end)
  end

  def handle_event("hide_inherited_for_children", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      sheet = socket.assigns.sheet

      case Sheets.hide_for_children(sheet, block_id) do
        {:ok, updated_sheet} ->
          {:noreply,
           socket
           |> assign(:sheet, updated_sheet)
           |> put_flash(:info, gettext("Property hidden from children."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not hide property."))}
      end
    end)
  end

  def handle_event("unhide_inherited_for_children", %{"id" => block_id}, socket) do
    with_authorization(socket, fn socket ->
      block_id = to_integer(block_id)
      sheet = socket.assigns.sheet

      case Sheets.unhide_for_children(sheet, block_id) do
        {:ok, updated_sheet} ->
          {:noreply,
           socket
           |> assign(:sheet, updated_sheet)
           |> put_flash(:info, gettext("Property visible to children again."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not unhide property."))}
      end
    end)
  end

  def handle_event("navigate_to_source", %{"id" => block_id}, socket) do
    block_id = to_integer(block_id)
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)
    source_sheet = Sheets.get_source_sheet(block)

    if source_sheet do
      workspace = socket.assigns.workspace
      project = socket.assigns.project

      {:noreply,
       push_navigate(socket,
         to: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{source_sheet.id}"
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Source sheet not found."))}
    end
  end

  def handle_event("change_block_scope", %{"scope" => scope}, socket)
      when scope in ["self", "children"] do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block

      if block.scope == scope do
        {:noreply, socket}
      else
        case Sheets.update_block(block, %{scope: scope}) do
          {:ok, updated_block} ->
            maybe_create_version(socket)
            notify_parent(socket, :saved)

            socket =
              socket
              |> assign(:configuring_block, updated_block)

            # When changing from "self" to "children", check for existing descendants
            # and open propagation modal if any exist
            socket =
              if scope == "children" do
                descendant_ids = Sheets.get_descendant_sheet_ids(socket.assigns.sheet.id)

                if descendant_ids != [] do
                  assign(socket, :propagation_block, updated_block)
                else
                  socket
                end
              else
                assign(socket, :propagation_block, nil)
              end

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not change scope."))}
        end
      end
    end)
  end

  def handle_event("toggle_required", _params, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.configuring_block
      new_value = !block.required

      case Sheets.update_block(block, %{required: new_value}) do
        {:ok, updated_block} ->
          notify_parent(socket, :saved)

          {:noreply,
           socket
           |> assign(:configuring_block, updated_block)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update required flag."))}
      end
    end)
  end

  # ===========================================================================
  # Propagation Events
  # ===========================================================================

  def handle_event("open_propagation_modal", %{"block-id" => block_id}, socket) do
    block_id = to_integer(block_id)
    block = Sheets.get_block_in_project!(block_id, socket.assigns.project.id)
    {:noreply, assign(socket, :propagation_block, block)}
  end

  def handle_event("cancel_propagation", _params, socket) do
    {:noreply, assign(socket, :propagation_block, nil)}
  end

  def handle_event("propagate_property", %{"sheet_ids" => sheet_ids_json}, socket) do
    with_authorization(socket, fn socket ->
      block = socket.assigns.propagation_block

      case Jason.decode(sheet_ids_json) do
        {:ok, sheet_ids} when is_list(sheet_ids) ->
          case Sheets.propagate_to_descendants(block, sheet_ids) do
            {:ok, count} ->
              {:noreply,
               socket
               |> assign(:propagation_block, nil)
               |> put_flash(
                 :info,
                 gettext("Property propagated to %{count} pages.", count: count)
               )}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, gettext("Could not propagate property."))}
          end

        _ ->
          {:noreply, put_flash(socket, :error, gettext("Invalid sheet selection."))}
      end
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp with_authorization(socket, fun) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to edit."))}
    end
  end

  defp handle_block_result(socket, {:ok, _blocks}) do
    maybe_create_version(socket)
    notify_parent(socket, :saved)
    {:noreply, socket}
  end

  defp handle_block_result(socket, {:error, message}) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp maybe_create_version(socket) do
    sheet = socket.assigns.sheet
    user_id = socket.assigns.current_user_id
    Sheets.maybe_create_version(sheet, user_id)
  end

  defp notify_parent(_socket, status) do
    send(self(), {:content_tab, status})
  end

  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  defp enrich_with_references(blocks, project_id) do
    Enum.map(blocks, fn block ->
      if block.type == "reference" do
        target_type = get_in(block.value, ["target_type"])
        target_id = get_in(block.value, ["target_id"])
        reference_target = Sheets.get_reference_target(target_type, target_id, project_id)
        Map.put(block, :reference_target, reference_target)
      else
        Map.put(block, :reference_target, nil)
      end
    end)
  end

  # ===========================================================================
  # Sub-components
  # ===========================================================================

  attr :source_sheet, :map, required: true
  attr :block_count, :integer, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  defp inherited_section_header(assigns) do
    ~H"""
    <div class="flex items-center gap-2 mb-2 px-2 sm:px-8 md:px-16">
      <.icon name="arrow-up-right" class="size-4 text-info" />
      <span class="text-xs text-base-content/50 uppercase tracking-wider">
        {gettext("Inherited from")}
      </span>
      <.link
        navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@source_sheet.id}"}
        class="text-sm font-medium text-info hover:underline"
      >
        {@source_sheet.name}
      </.link>
      <span class="text-xs text-base-content/40">({@block_count})</span>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :editing_block_id, :any, default: nil
  attr :target, :any, default: nil

  defp inherited_block_wrapper(assigns) do
    ~H"""
    <div class="relative group/inherited">
      <.block_component
        block={@block}
        can_edit={@can_edit}
        editing_block_id={@editing_block_id}
        target={@target}
      />
      <%!-- Inherited block actions overlay --%>
      <div class="absolute top-1 right-2 flex items-center gap-1 opacity-0 group-hover/inherited:opacity-100 transition-opacity">
        <%!-- Go to source --%>
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square tooltip tooltip-left"
          data-tip={gettext("Go to source")}
          phx-click="navigate_to_source"
          phx-value-id={@block.id}
          phx-target={@target}
        >
          <.icon name="arrow-up-right" class="size-3 text-info" />
        </button>
        <%!-- Context menu --%>
        <div class="dropdown dropdown-end">
          <div tabindex="0" role="button" class="btn btn-ghost btn-xs btn-square">
            <.icon name="ellipsis-vertical" class="size-3" />
          </div>
          <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52">
            <li>
              <button phx-click="navigate_to_source" phx-value-id={@block.id} phx-target={@target}>
                <.icon name="arrow-up-right" class="size-4" />
                {gettext("Go to source")}
              </button>
            </li>
            <li>
              <button
                phx-click="detach_inherited_block"
                phx-value-id={@block.id}
                phx-target={@target}
              >
                <.icon name="scissors" class="size-4" />
                {gettext("Detach property")}
              </button>
            </li>
            <li>
              <button
                phx-click="hide_inherited_for_children"
                phx-value-id={@block.inherited_from_block_id}
                phx-target={@target}
              >
                <.icon name="eye-off" class="size-4" />
                {gettext("Hide for children")}
              </button>
            </li>
          </ul>
        </div>
      </div>
      <%!-- Required indicator --%>
      <div
        :if={@block.required}
        class="absolute top-1 left-2 text-error text-xs font-bold"
        title={gettext("Required")}
      >
        *
      </div>
    </div>
    """
  end

  attr :children, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  defp children_sheets_section(assigns) do
    ~H"""
    <div class="mt-12 pt-8 border-t border-base-300">
      <h2 class="text-lg font-semibold mb-4">{gettext("Subsheets")}</h2>
      <div class="space-y-2">
        <.link
          :for={child <- @children}
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{child.id}"}
          class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
        >
          <.sheet_avatar avatar_asset={child.avatar_asset} name={child.name} size="md" />
          <span>{child.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
