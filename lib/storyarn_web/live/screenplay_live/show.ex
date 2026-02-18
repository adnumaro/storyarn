defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  require Logger

  alias Storyarn.Flows
  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.CharacterExtension
  alias Storyarn.Screenplays.ContentUtils
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.TiptapSerialization
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.ConditionBuilder
  alias StoryarnWeb.Components.InstructionBuilder

  # Title page field validation
  @valid_title_fields ~w(title credit author draft_date contact)

  # Dual dialogue field validation
  @valid_dual_sides ~w(left right)
  @valid_dual_fields ~w(character parenthetical dialogue)

  # All types managed by the unified TipTap editor (text blocks + atom NodeViews)
  @editor_types ~w(scene_heading action character dialogue parenthetical transition note section page_break hub_marker jump_marker title_page conditional instruction response dual_dialogue)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      screenplays_tree={@screenplays_tree}
      active_tool={:screenplays}
      selected_screenplay_id={to_string(@screenplay.id)}
      current_path={
        ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}"
      }
      can_edit={@can_edit}
    >
      <div class="screenplay-container -mx-12 lg:-mx-8 -my-6 lg:-my-8 px-12 lg:px-8 py-6 lg:py-8">
        <div class="screenplay-toolbar" id="screenplay-toolbar">
          <div class="screenplay-toolbar-left">
            <h1
              :if={@can_edit}
              id="screenplay-title"
              class="screenplay-toolbar-title"
              contenteditable="true"
              phx-hook="EditableTitle"
              phx-update="ignore"
              data-placeholder={dgettext("screenplays", "Untitled")}
              data-name={@screenplay.name}
            >
            {@screenplay.name}
          </h1>
            <h1 :if={!@can_edit} class="screenplay-toolbar-title">
              {@screenplay.name}
            </h1>
          </div>
          <div class="screenplay-toolbar-right">
            <span class="screenplay-toolbar-badge" id="screenplay-element-count">
              {dngettext("screenplays", "%{count} element", "%{count} elements", length(@elements))}
            </span>
            <span
              :if={Screenplay.draft?(@screenplay)}
              class="screenplay-toolbar-badge screenplay-toolbar-draft"
            >
              {dgettext("screenplays", "Draft")}
            </span>
            <button
              type="button"
              class={["sp-toolbar-btn", @read_mode && "sp-toolbar-btn-active"]}
              phx-click="toggle_read_mode"
              title={if @read_mode, do: dgettext("screenplays", "Exit read mode"), else: dgettext("screenplays", "Read mode")}
            >
              <.icon name={if @read_mode, do: "pencil", else: "book-open"} class="size-4" />
            </button>
            <a
              href={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}/export/fountain"
              }
              class="sp-toolbar-btn"
              title={dgettext("screenplays", "Export as Fountain")}
              download
            >
              <.icon name="upload" class="size-4" />
            </a>
            <button
              :if={@can_edit}
              type="button"
              class="sp-toolbar-btn"
              title={dgettext("screenplays", "Import Fountain")}
              id="screenplay-import-btn"
              phx-hook="FountainImport"
            >
              <.icon name="download" class="size-4" />
            </button>
            <span class="screenplay-toolbar-separator"></span>
            <%= case @link_status do %>
              <% :unlinked -> %>
                <button
                  :if={@can_edit}
                  class="sp-sync-btn"
                  phx-click="create_flow_from_screenplay"
                >
                  <.icon name="git-branch" class="size-3.5" />
                  {dgettext("screenplays", "Create Flow")}
                </button>
              <% :linked -> %>
                <button
                  class="sp-sync-badge sp-sync-linked"
                  phx-click="navigate_to_flow"
                >
                  <.icon name="git-branch" class="size-3" />
                  {@linked_flow.name}
                </button>
                <button
                  :if={@can_edit}
                  class="sp-sync-btn"
                  phx-click="sync_to_flow"
                  title={dgettext("screenplays", "Push screenplay to flow")}
                >
                  <.icon name="upload" class="size-3.5" />
                  {dgettext("screenplays", "To Flow")}
                </button>
                <button
                  :if={@can_edit}
                  class="sp-sync-btn"
                  phx-click="sync_from_flow"
                  title={dgettext("screenplays", "Update screenplay from flow")}
                >
                  <.icon name="download" class="size-3.5" />
                  {dgettext("screenplays", "From Flow")}
                </button>
                <button
                  :if={@can_edit}
                  class="sp-sync-btn sp-sync-btn-subtle"
                  phx-click="unlink_flow"
                >
                  <.icon name="unlink" class="size-3.5" />
                </button>
              <% status when status in [:flow_deleted, :flow_missing] -> %>
                <span class="sp-sync-badge sp-sync-warning">
                  <.icon name="alert-triangle" class="size-3" />
                  {if status == :flow_deleted,
                    do: dgettext("screenplays", "Flow trashed"),
                    else: dgettext("screenplays", "Flow missing")}
                </span>
                <button
                  :if={@can_edit}
                  class="sp-sync-btn sp-sync-btn-subtle"
                  phx-click="unlink_flow"
                >
                  <.icon name="unlink" class="size-3.5" />
                  {dgettext("screenplays", "Unlink")}
                </button>
            <% end %>
          </div>
        </div>
        <div
          id="screenplay-page"
          class={[
            "screenplay-page",
            @read_mode && "screenplay-read-mode"
          ]}
        >
          <%!-- Unified TipTap editor — always rendered, read mode toggles editable --%>
          <div
            id="screenplay-editor"
            phx-hook="ScreenplayEditor"
            data-content={Jason.encode!(@editor_doc)}
            data-can-edit={to_string(@can_edit)}
            data-read-mode={to_string(@read_mode)}
            data-variables={Jason.encode!(@project_variables)}
            data-linked-pages={Jason.encode!(@linked_pages)}
            data-translations={Jason.encode!(screenplay_translations())}
            data-highlight-element={@highlight_element_id}
            phx-update="ignore"
          >
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => screenplay_id
        },
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
        screenplay = Screenplays.get_screenplay!(project.id, screenplay_id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:screenplay, screenplay)
          |> assign(:read_mode, false)
          # Defaults for disconnected render — real data loaded on connect
          |> assign(:screenplays_tree, [])
          |> assign(:sheets_map, %{})
          |> assign(:elements, [])
          |> assign(:editor_doc, TiptapSerialization.elements_to_doc([]))
          |> assign(:project_variables, [])
          |> assign(:link_status, :unlinked)
          |> assign(:linked_flow, nil)
          |> assign(:linked_pages, %{})
          |> assign(:highlight_element_id, nil)

        socket =
          if connected?(socket), do: load_connected_data(socket, screenplay), else: socket

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("screenplays", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp load_connected_data(socket, screenplay) do
    project = socket.assigns.project
    elements = Screenplays.list_elements(screenplay.id)
    project_variables = Sheets.list_project_variables(project.id)
    all_sheets = Sheets.list_all_sheets(project.id)
    sheets_map = Map.new(all_sheets, &{&1.id, &1})
    screenplays_tree = Screenplays.list_screenplays_tree(project.id)
    {link_status, linked_flow} = detect_link_status(screenplay)

    socket
    |> assign(:screenplays_tree, screenplays_tree)
    |> assign(:sheets_map, sheets_map)
    |> assign_elements_with_editor_doc(elements)
    |> assign(:project_variables, project_variables)
    |> assign(:link_status, link_status)
    |> assign(:linked_flow, linked_flow)
    |> assign(:linked_pages, load_linked_pages(screenplay))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :highlight_element_id, parse_int(params["element"]))}
  end

  # ---------------------------------------------------------------------------
  # Read mode
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_read_mode", _params, socket) do
    new_mode = !socket.assigns.read_mode

    {:noreply,
     socket
     |> assign(:read_mode, new_mode)
     |> push_event("set_read_mode", %{read_mode: new_mode})}
  end

  # ---------------------------------------------------------------------------
  # Element editing handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("delete_element", %{"id" => id}, socket) do
    with_edit_permission(socket, fn ->
      do_delete_element(socket, id)
    end)
  end

  # ---------------------------------------------------------------------------
  # Unified editor sync handler
  # ---------------------------------------------------------------------------

  def handle_event("sync_editor_content", %{"elements" => client_elements}, socket) do
    with_edit_permission(socket, fn ->
      do_sync_editor_content(socket, client_elements)
    end)
  end

  # ---------------------------------------------------------------------------
  # Interactive block handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_screenplay_condition",
        %{"element-id" => id, "condition" => condition},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_update_screenplay_condition(socket, id, condition)
    end)
  end

  def handle_event(
        "update_screenplay_instruction",
        %{"element-id" => id, "assignments" => assignments},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_update_screenplay_instruction(socket, id, assignments)
    end)
  end

  def handle_event("add_response_choice", %{"element-id" => id}, socket) do
    with_edit_permission(socket, fn ->
      do_add_response_choice(socket, id)
    end)
  end

  def handle_event(
        "remove_response_choice",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_remove_response_choice(socket, id, choice_id)
    end)
  end

  def handle_event(
        "update_response_choice_text",
        %{"element-id" => id, "choice-id" => choice_id, "value" => text},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_update_response_choice_text(socket, id, choice_id, text)
    end)
  end

  def handle_event(
        "toggle_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_toggle_choice_condition(socket, id, choice_id)
    end)
  end

  def handle_event(
        "toggle_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_toggle_choice_instruction(socket, id, choice_id)
    end)
  end

  def handle_event(
        "update_response_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id, "condition" => condition},
        socket
      ) do
    with_edit_permission(socket, fn ->
      update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "condition", Condition.sanitize(condition))
      end)
    end)
  end

  def handle_event(
        "update_response_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id, "assignments" => assignments},
        socket
      ) do
    with_edit_permission(socket, fn ->
      update_choice_field(socket, id, choice_id, fn choice ->
        Map.put(choice, "instruction", Instruction.sanitize(assignments))
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Dual dialogue handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_dual_dialogue",
        %{"element-id" => id, "side" => side, "field" => field, "value" => value},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_update_dual_dialogue(socket, id, side, field, value)
    end)
  end

  def handle_event(
        "toggle_dual_parenthetical",
        %{"element-id" => id, "side" => side},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_toggle_dual_parenthetical(socket, id, side)
    end)
  end

  # ---------------------------------------------------------------------------
  # Title page handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "update_title_page",
        %{"element-id" => id, "field" => field, "value" => value},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_update_title_page(socket, id, field, value)
    end)
  end

  # ---------------------------------------------------------------------------
  # Import handler
  # ---------------------------------------------------------------------------

  def handle_event("import_fountain", %{"content" => content}, socket) do
    with_edit_permission(socket, fn ->
      do_import_fountain(socket, content)
    end)
  end

  # ---------------------------------------------------------------------------
  # Linked page handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "create_linked_page",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_create_linked_page(socket, eid, cid)
    end)
  end

  def handle_event(
        "navigate_to_linked_page",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    do_navigate_to_linked_page(socket, eid, cid)
  end

  def handle_event(
        "unlink_choice_screenplay",
        %{"element-id" => eid, "choice-id" => cid},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_unlink_choice_screenplay(socket, eid, cid)
    end)
  end

  def handle_event("generate_all_linked_pages", %{"element-id" => eid}, socket) do
    with_edit_permission(socket, fn ->
      do_generate_all_linked_pages(socket, eid)
    end)
  end

  # ---------------------------------------------------------------------------
  # Character sheet reference handlers
  # ---------------------------------------------------------------------------

  def handle_event("search_character_sheets", %{"query" => query}, socket) do
    results =
      Sheets.search_referenceable(socket.assigns.project.id, query, ["sheet"])
      |> Enum.map(fn item -> %{id: item.id, name: item.name, shortcut: item.shortcut} end)

    {:noreply, push_event(socket, "character_sheet_results", %{items: results})}
  end

  def handle_event("set_character_sheet", %{"id" => id, "sheet_id" => sheet_id}, socket) do
    with_edit_permission(socket, fn ->
      do_set_character_sheet(socket, id, parse_int(sheet_id))
    end)
  end

  def handle_event("mention_suggestions", %{"query" => query}, socket) do
    results =
      Sheets.search_referenceable(socket.assigns.project.id, query, ["sheet"])
      |> Enum.map(fn item ->
        %{id: to_string(item.id), name: item.name, shortcut: item.shortcut, type: "sheet"}
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: results})}
  end

  def handle_event("navigate_to_sheet", %{"sheet_id" => sheet_id}, socket) do
    sheet_id = parse_int(sheet_id)
    sheet = sheet_id && Map.get(socket.assigns.sheets_map, sheet_id)

    if sheet do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{sheet.id}"
       )}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Toolbar handlers
  # ---------------------------------------------------------------------------

  def handle_event("save_name", %{"name" => name}, socket) do
    with_edit_permission(socket, fn ->
      case Screenplays.update_screenplay(socket.assigns.screenplay, %{name: name}) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:screenplay, updated)
           |> reload_screenplays_tree()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not save screenplay name."))}
      end
    end)
  end

  def handle_event("create_flow_from_screenplay", _params, socket) do
    with_edit_permission(socket, fn ->
      screenplay = socket.assigns.screenplay

      with {:ok, flow} <- Screenplays.ensure_flow(screenplay),
           screenplay = Screenplays.get_screenplay!(screenplay.project_id, screenplay.id),
           {:ok, _flow} <- Screenplays.sync_to_flow(screenplay) do
        screenplay = Screenplays.get_screenplay!(screenplay.project_id, screenplay.id)

        {:noreply,
         socket
         |> assign(:screenplay, screenplay)
         |> assign(:link_status, :linked)
         |> assign(:linked_flow, flow)
         |> put_flash(:info, dgettext("screenplays", "Flow created and synced."))}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not create flow."))}
      end
    end)
  end

  def handle_event("sync_to_flow", _params, socket) do
    with_edit_permission(socket, fn ->
      do_sync_to_flow(socket)
    end)
  end

  def handle_event("sync_from_flow", _params, socket) do
    with_edit_permission(socket, fn ->
      do_sync_from_flow(socket)
    end)
  end

  def handle_event("unlink_flow", _params, socket) do
    with_edit_permission(socket, fn ->
      screenplay = socket.assigns.screenplay

      case Screenplays.unlink_flow(screenplay) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:screenplay, updated)
           |> assign(:link_status, :unlinked)
           |> assign(:linked_flow, nil)
           |> put_flash(:info, dgettext("screenplays", "Flow unlinked."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not unlink flow."))}
      end
    end)
  end

  def handle_event("navigate_to_flow", _params, socket) do
    flow = socket.assigns.linked_flow

    if flow do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
       )}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar event handlers
  # ---------------------------------------------------------------------------

  def handle_event("set_pending_delete_screenplay", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_screenplay", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete_screenplay", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_screenplay", %{"id" => screenplay_id}, socket) do
    with_edit_permission(socket, fn ->
      do_delete_screenplay(socket, screenplay_id)
    end)
  end

  def handle_event("create_screenplay", _params, socket) do
    do_create_screenplay(socket, %{})
  end

  def handle_event("create_child_screenplay", %{"parent-id" => parent_id}, socket) do
    do_create_screenplay(socket, %{parent_id: parent_id})
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_move_to_parent(socket, item_id, new_parent_id, position)
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers — extracted handler bodies
  # ---------------------------------------------------------------------------

  defp do_sync_editor_content(socket, client_elements) when is_list(client_elements) do
    screenplay = socket.assigns.screenplay
    existing = socket.assigns.elements
    client_ids = extract_client_ids(client_elements)

    delete_removed_editor_elements(existing, client_ids)

    existing_by_id = Map.new(existing, &{&1.id, &1})

    {ordered_ids, changed_ids} =
      upsert_client_elements(screenplay, client_elements, existing_by_id)

    reorder_after_sync(screenplay, ordered_ids)

    elements = Screenplays.list_elements(screenplay.id)

    # Only update references for elements whose content or data actually changed
    elements
    |> Enum.filter(&(&1.id in changed_ids))
    |> Enum.each(&Sheets.update_screenplay_element_references/1)

    {:noreply, assign_elements(socket, elements)}
  end

  defp do_sync_editor_content(socket, _), do: {:noreply, socket}

  defp extract_client_ids(client_elements) do
    client_elements
    |> Enum.map(& &1["element_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp delete_removed_editor_elements(existing, client_ids) do
    existing
    |> Enum.filter(&(&1.type in @editor_types))
    |> Enum.reject(&(&1.id in client_ids))
    |> Enum.each(fn el ->
      Sheets.delete_screenplay_element_references(el.id)
      Screenplays.delete_element(el)
    end)
  end

  defp upsert_client_elements(screenplay, client_elements, existing_by_id) do
    {ordered_ids, changed_ids} =
      Enum.reduce(client_elements, {[], MapSet.new()}, fn el, {ids, changed} ->
        element_id = el["element_id"] && parse_int(el["element_id"])

        type = el["type"] || "action"

        attrs = %{
          type: type,
          content: ContentUtils.sanitize_html(el["content"]),
          data: sanitize_element_data(type, el["data"])
        }

        existing_el = element_id && Map.get(existing_by_id, element_id)

        case upsert_single_element(screenplay, attrs, existing_el) do
          {:created, id} -> {ids ++ [id], MapSet.put(changed, id)}
          {:updated, id} -> {ids ++ [id], MapSet.put(changed, id)}
          {:unchanged, id} -> {ids ++ [id], changed}
          :error -> {ids, changed}
        end
      end)

    {ordered_ids, changed_ids}
  end

  defp upsert_single_element(screenplay, attrs, nil) do
    case Screenplays.create_element(screenplay, attrs) do
      {:ok, created} -> {:created, created.id}
      _ -> :error
    end
  end

  defp upsert_single_element(_screenplay, attrs, existing_el) do
    changed? =
      existing_el.content != attrs.content ||
        existing_el.data != attrs.data ||
        existing_el.type != attrs.type

    case Screenplays.update_element(existing_el, attrs) do
      {:ok, _} ->
        if changed?, do: {:updated, existing_el.id}, else: {:unchanged, existing_el.id}

      {:error, changeset} ->
        Logger.warning(
          "Failed to update screenplay element #{existing_el.id}: #{inspect(changeset.errors)}"
        )

        {:unchanged, existing_el.id}
    end
  end

  defp reorder_after_sync(screenplay, ordered_ids) do
    if ordered_ids != [] do
      Screenplays.reorder_elements(screenplay.id, ordered_ids)
    end
  end

  defp do_delete_element(socket, id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        prev = Enum.find(socket.assigns.elements, &(&1.position == element.position - 1))
        persist_element_deletion(socket, element, prev)
    end
  end

  defp persist_element_deletion(socket, element, prev) do
    Sheets.delete_screenplay_element_references(element.id)

    case Screenplays.delete_element(element) do
      {:ok, _} ->
        reloaded = Screenplays.list_elements(socket.assigns.screenplay.id)

        socket = assign_elements(socket, reloaded)

        socket =
          if prev do
            push_event(socket, "focus_element", %{id: prev.id})
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not delete element."))}
    end
  end

  defp do_update_dual_dialogue(socket, id, side, field, value)
       when side in @valid_dual_sides and field in @valid_dual_fields do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_dual_dialogue_field(socket, element, side, field, value)
    end
  end

  defp do_update_dual_dialogue(socket, _id, _side, _field, _value), do: {:noreply, socket}

  defp persist_dual_dialogue_field(socket, element, side, field, value) do
    data = element.data || %{}
    side_data = data[side] || %{}

    sanitized_value =
      case field do
        f when f in ~w(dialogue parenthetical) -> ContentUtils.sanitize_html(value)
        "character" -> sanitize_plain_text(value)
      end

    updated_side = Map.put(side_data, field, sanitized_value)
    updated_data = Map.put(data, side, updated_side)

    case Screenplays.update_element(element, %{data: updated_data}) do
      {:ok, updated} ->
        socket = update_element_in_list(socket, updated)
        {:noreply, push_element_data_updated(socket, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not update dual dialogue."))}
    end
  end

  defp do_toggle_dual_parenthetical(socket, id, side) when side in @valid_dual_sides do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        data = element.data || %{}
        side_data = data[side] || %{}

        updated_side =
          if side_data["parenthetical"] != nil,
            do: Map.put(side_data, "parenthetical", nil),
            else: Map.put(side_data, "parenthetical", "")

        updated_data = Map.put(data, side, updated_side)

        case Screenplays.update_element(element, %{data: updated_data}) do
          {:ok, updated} ->
            socket = update_element_in_list(socket, updated)
            {:noreply, push_element_data_updated(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not toggle parenthetical."))}
        end
    end
  end

  defp do_toggle_dual_parenthetical(socket, _id, _side), do: {:noreply, socket}

  defp do_update_title_page(socket, id, field, value)
       when field in @valid_title_fields do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        data = element.data || %{}
        updated_data = Map.put(data, field, sanitize_plain_text(value))

        case Screenplays.update_element(element, %{data: updated_data}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> update_element_in_list(updated)
             |> push_element_data_updated(updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not update title page."))}
        end
    end
  end

  defp do_update_title_page(socket, _id, _field, _value), do: {:noreply, socket}

  defp do_import_fountain(socket, content) when is_binary(content) do
    parsed = Screenplays.parse_fountain(content)

    if parsed == [] do
      {:noreply, put_flash(socket, :error, dgettext("screenplays", "No content found in imported file."))}
    else
      screenplay = socket.assigns.screenplay

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:delete_existing, fn _repo, _ ->
          delete_all_elements(socket.assigns.elements)
        end)
        |> Ecto.Multi.run(:create_imported, fn _repo, _ ->
          create_elements_from_parsed(screenplay, parsed)
        end)
        |> Repo.transaction()

      case result do
        {:ok, _} ->
          elements = Screenplays.list_elements(screenplay.id)
          elements = create_character_sheets_from_import(socket.assigns.project, elements)

          {:noreply,
           socket
           |> assign_elements(elements)
           |> refresh_sheets_map()
           |> push_editor_content(elements)
           |> put_flash(:info, dgettext("screenplays", "Fountain file imported successfully."))}

        {:error, _step, _reason, _changes} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not import file."))}
      end
    end
  end

  defp do_import_fountain(socket, _content), do: {:noreply, socket}

  defp delete_all_elements(elements) do
    Enum.each(elements, fn el ->
      Sheets.delete_screenplay_element_references(el.id)
      {:ok, _} = Screenplays.delete_element(el)
    end)

    {:ok, :deleted}
  end

  defp create_elements_from_parsed(screenplay, parsed) do
    created =
      Enum.map(parsed, fn attrs ->
        {:ok, el} = Screenplays.create_element(screenplay, attrs)
        el
      end)

    {:ok, created}
  end

  defp create_character_sheets_from_import(project, elements) do
    followed_by_dialogue = character_ids_followed_by_dialogue(elements)
    character_elements = Enum.filter(elements, &character_with_dialogue?(&1, followed_by_dialogue))

    name_to_sheet = create_sheets_for_characters(project, character_elements)

    Enum.map(elements, fn el ->
      maybe_link_character_sheet(el, followed_by_dialogue, name_to_sheet)
    end)
  end

  # Build a set of element IDs where a character cue is followed by dialogue/parenthetical.
  defp character_ids_followed_by_dialogue(elements) do
    elements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(MapSet.new(), fn [a, b], acc ->
      if a.type == "character" and b.type in ~w(dialogue parenthetical),
        do: MapSet.put(acc, a.id),
        else: acc
    end)
  end

  defp character_with_dialogue?(el, followed_set),
    do: el.type == "character" and el.id in followed_set

  defp create_sheets_for_characters(project, character_elements) do
    character_elements
    |> Enum.map(&CharacterExtension.base_name(&1.content))
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&valid_character_sheet_name?/1)
    |> Enum.uniq()
    |> Map.new(&create_sheet_for_name(project, &1))
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp create_sheet_for_name(project, name) do
    case Sheets.create_sheet(project, %{name: name}) do
      {:ok, sheet} -> {name, sheet}
      {:error, _} -> {name, nil}
    end
  end

  defp maybe_link_character_sheet(el, followed_set, name_to_sheet) do
    if character_with_dialogue?(el, followed_set),
      do: link_sheet_to_element(el, name_to_sheet),
      else: el
  end

  defp link_sheet_to_element(el, name_to_sheet) do
    base = CharacterExtension.base_name(el.content)

    case Map.get(name_to_sheet, base) do
      nil -> el
      sheet -> update_element_sheet(el, sheet)
    end
  end

  defp update_element_sheet(el, sheet) do
    data = Map.put(el.data || %{}, "sheet_id", sheet.id)

    case Screenplays.update_element(el, %{data: data}) do
      {:ok, updated} -> updated
      {:error, _} -> el
    end
  end

  defp refresh_sheets_map(socket) do
    all_sheets = Sheets.list_all_sheets(socket.assigns.project.id)
    assign(socket, :sheets_map, Map.new(all_sheets, &{&1.id, &1}))
  end

  # Filter out names that are clearly not characters (misclassified transitions,
  # scene descriptions, action lines). Real character names don't end with
  # punctuation like : . , and don't contain scene heading markers.
  defp valid_character_sheet_name?(name) do
    trimmed = String.trim(name)

    trimmed != "" and
      not String.ends_with?(trimmed, ":") and
      not String.ends_with?(trimmed, ".") and
      not String.ends_with?(trimmed, ",") and
      not String.starts_with?(trimmed, ">") and
      not Regex.match?(~r"\b(EXT|INT|EST)\b[./]", trimmed)
  end

  defp do_update_screenplay_condition(socket, id, condition) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        sanitized = Condition.sanitize(condition)
        data = Map.put(element.data || %{}, "condition", sanitized)

        case Screenplays.update_element(element, %{data: data}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> update_element_in_list(updated)
             |> push_element_data_updated(updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not save condition."))}
        end
    end
  end

  defp do_update_screenplay_instruction(socket, id, assignments) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        sanitized = Instruction.sanitize(assignments)
        data = Map.put(element.data || %{}, "assignments", sanitized)

        case Screenplays.update_element(element, %{data: data}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> update_element_in_list(updated)
             |> push_element_data_updated(updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not save instruction."))}
        end
    end
  end

  defp do_add_response_choice(socket, id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        new_choice = %{"id" => Ecto.UUID.generate(), "text" => ""}
        data = element.data || %{}
        choices = (data["choices"] || []) ++ [new_choice]
        data = Map.put(data, "choices", choices)

        case Screenplays.update_element(element, %{data: data}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> update_element_in_list(updated)
             |> push_element_data_updated(updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not add choice."))}
        end
    end
  end

  defp do_remove_response_choice(socket, id, choice_id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        data = element.data || %{}
        choices = Enum.reject(data["choices"] || [], &(&1["id"] == choice_id))
        data = Map.put(data, "choices", choices)

        case Screenplays.update_element(element, %{data: data}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> update_element_in_list(updated)
             |> push_element_data_updated(updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not remove choice."))}
        end
    end
  end

  defp do_update_response_choice_text(socket, id, choice_id, text) do
    update_choice_field(socket, id, choice_id, fn choice ->
      Map.put(choice, "text", text)
    end)
  end

  defp do_toggle_choice_condition(socket, id, choice_id) do
    update_choice_field(socket, id, choice_id, fn choice ->
      if choice["condition"],
        do: Map.delete(choice, "condition"),
        else: Map.put(choice, "condition", Condition.new())
    end)
  end

  defp do_toggle_choice_instruction(socket, id, choice_id) do
    update_choice_field(socket, id, choice_id, fn choice ->
      if choice["instruction"],
        do: Map.delete(choice, "instruction"),
        else: Map.put(choice, "instruction", [])
    end)
  end

  defp do_set_character_sheet(socket, id, sheet_id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_character_sheet(socket, element, sheet_id)
    end
  end

  defp persist_character_sheet(socket, element, sheet_id) do
    sheet_id = parse_int(sheet_id)
    sheet = sheet_id && Map.get(socket.assigns.sheets_map, sheet_id)
    name = if sheet, do: String.upcase(sheet.name), else: element.content
    data = Map.put(element.data || %{}, "sheet_id", sheet_id)

    case Screenplays.update_element(element, %{content: name, data: data}) do
      {:ok, updated} ->
        Sheets.update_screenplay_element_references(updated)
        {:noreply, update_element_in_list(socket, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not set character sheet."))}
    end
  end

  defp do_sync_to_flow(socket) do
    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay is not linked to a flow."))}
    else
      case Screenplays.sync_to_flow(socket.assigns.screenplay) do
        {:ok, _flow} ->
          {:noreply, put_flash(socket, :info, dgettext("screenplays", "Screenplay synced to flow."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not sync screenplay."))}
      end
    end
  end

  defp do_sync_from_flow(socket) do
    screenplay = socket.assigns.screenplay

    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay is not linked to a flow."))}
    else
      case Screenplays.sync_from_flow(screenplay) do
        {:ok, _screenplay} ->
          elements = Screenplays.list_elements(screenplay.id)

          {:noreply,
           socket
           |> assign_elements(elements)
           |> push_editor_content(elements)
           |> put_flash(:info, dgettext("screenplays", "Screenplay updated from flow."))}

        {:error, :no_entry_node} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Flow has no entry node."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not sync from flow."))}
      end
    end
  end

  defp do_delete_screenplay(socket, screenplay_id) do
    case Screenplays.get_screenplay(socket.assigns.project.id, screenplay_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay not found."))}

      screenplay ->
        persist_screenplay_deletion(socket, screenplay)
    end
  end

  defp persist_screenplay_deletion(socket, screenplay) do
    case Screenplays.delete_screenplay(screenplay) do
      {:ok, _} ->
        if to_string(screenplay.id) == to_string(socket.assigns.screenplay.id) do
          {:noreply,
           socket
           |> put_flash(:info, dgettext("screenplays", "Screenplay moved to trash."))
           |> push_navigate(to: screenplays_path(socket))}
        else
          {:noreply,
           socket
           |> put_flash(:info, dgettext("screenplays", "Screenplay moved to trash."))
           |> reload_screenplays_tree()}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not delete screenplay."))}
    end
  end

  defp do_move_to_parent(socket, item_id, new_parent_id, position) do
    case Screenplays.get_screenplay(socket.assigns.project.id, item_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay not found."))}

      screenplay ->
        new_parent_id = parse_int(new_parent_id)
        position = parse_int(position) || 0

        case Screenplays.move_screenplay_to_position(screenplay, new_parent_id, position) do
          {:ok, _} ->
            {:noreply, reload_screenplays_tree(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not move screenplay."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers — linked pages
  # ---------------------------------------------------------------------------

  defp do_create_linked_page(socket, element_id, choice_id) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        screenplay = socket.assigns.screenplay

        case Screenplays.create_linked_page(screenplay, element, choice_id) do
          {:ok, _child, updated_element} ->
            new_linked_pages = load_linked_pages(screenplay)

            {:noreply,
             socket
             |> update_element_in_list(updated_element)
             |> assign(:linked_pages, new_linked_pages)
             |> push_event("linked_pages_updated", %{linked_pages: new_linked_pages})
             |> push_element_data_updated(updated_element)
             |> reload_screenplays_tree()
             |> put_flash(:info, dgettext("screenplays", "Linked page created."))}

          {:error, :choice_not_found} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Choice not found."))}

          {:error, :already_linked} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Choice already has a linked page."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not create linked page."))}
        end
    end
  end

  defp do_navigate_to_linked_page(socket, element_id, choice_id) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        choice = Screenplays.find_choice(element, choice_id)
        linked_id = choice && choice["linked_screenplay_id"]

        if linked_id && valid_navigation_target?(socket, linked_id) do
          {:noreply, push_navigate(socket, to: screenplays_path(socket, linked_id))}
        else
          {:noreply, socket}
        end
    end
  end

  defp valid_navigation_target?(socket, screenplay_id) do
    Screenplays.screenplay_exists?(socket.assigns.project.id, screenplay_id)
  end

  defp do_unlink_choice_screenplay(socket, element_id, choice_id) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        case Screenplays.unlink_choice(element, choice_id) do
          {:ok, updated_element} ->
            {:noreply,
             socket
             |> update_element_in_list(updated_element)
             |> push_element_data_updated(updated_element)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not unlink choice."))}
        end
    end
  end

  defp do_generate_all_linked_pages(socket, element_id) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        screenplay = socket.assigns.screenplay
        choices = (element.data || %{})["choices"] || []
        unlinked = Enum.reject(choices, & &1["linked_screenplay_id"])

        case create_pages_for_choices(screenplay, element, unlinked) do
          {:ok, updated_element} ->
            new_linked_pages = load_linked_pages(screenplay)

            {:noreply,
             socket
             |> update_element_in_list(updated_element)
             |> assign(:linked_pages, new_linked_pages)
             |> push_event("linked_pages_updated", %{linked_pages: new_linked_pages})
             |> push_element_data_updated(updated_element)
             |> reload_screenplays_tree()
             |> put_flash(:info, dgettext("screenplays", "Linked pages created."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not create linked pages."))}
        end
    end
  end

  defp create_pages_for_choices(_screenplay, element, []), do: {:ok, element}

  defp create_pages_for_choices(screenplay, element, [choice | rest]) do
    case Screenplays.create_linked_page(screenplay, element, choice["id"]) do
      {:ok, _child, updated_element} ->
        create_pages_for_choices(screenplay, updated_element, rest)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_linked_pages(screenplay) do
    Screenplays.list_child_screenplays(screenplay.id)
    |> Map.new(fn s -> {s.id, s.name} end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers — general utilities
  # ---------------------------------------------------------------------------

  defp detect_link_status(%Screenplay{linked_flow_id: nil}), do: {:unlinked, nil}

  defp detect_link_status(%Screenplay{project_id: project_id, linked_flow_id: flow_id}) do
    case Flows.get_flow_including_deleted(project_id, flow_id) do
      nil ->
        {:flow_missing, nil}

      flow ->
        if Storyarn.Flows.Flow.deleted?(flow),
          do: {:flow_deleted, flow},
          else: {:linked, flow}
    end
  end

  defp with_edit_permission(socket, fun) do
    case authorize(socket, :edit_content) do
      :ok ->
        fun.()

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "You don't have permission to perform this action."))}
    end
  end

  defp do_create_screenplay(socket, extra_attrs) do
    with_edit_permission(socket, fn ->
      attrs = Map.merge(%{name: dgettext("screenplays", "Untitled")}, extra_attrs)

      case Screenplays.create_screenplay(socket.assigns.project, attrs) do
        {:ok, new_screenplay} ->
          {:noreply, push_navigate(socket, to: screenplays_path(socket, new_screenplay.id))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not create screenplay."))}
      end
    end)
  end

  defp parse_int(""), do: nil
  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp screenplays_path(socket, screenplay_id \\ nil)

  defp screenplays_path(socket, nil) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays"
  end

  defp screenplays_path(socket, screenplay_id) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{screenplay_id}"
  end

  defp reload_screenplays_tree(socket) do
    assign(
      socket,
      :screenplays_tree,
      Screenplays.list_screenplays_tree(socket.assigns.project.id)
    )
  end

  defp find_element(socket, id) do
    id =
      cond do
        is_integer(id) -> id
        is_binary(id) -> parse_int(id)
        true -> nil
      end

    if id, do: Enum.find(socket.assigns.elements, &(&1.id == id)), else: nil
  end

  defp update_element_in_list(socket, updated_element) do
    elements =
      Enum.map(socket.assigns.elements, fn el ->
        if el.id == updated_element.id, do: updated_element, else: el
      end)

    assign_elements(socket, elements)
  end

  # Mount/reconnect: computes editor_doc for initial render
  defp assign_elements_with_editor_doc(socket, elements) do
    socket
    |> assign(:elements, elements)
    |> assign(:editor_doc, TiptapSerialization.elements_to_doc(elements))
  end

  # Post-mount updates: skips editor_doc recomputation (client owns the doc)
  defp assign_elements(socket, elements) do
    assign(socket, :elements, elements)
  end

  # Push full editor content to TipTap after server-side bulk updates (e.g. flow sync).
  # The LiveViewBridge extension listens for "set_editor_content" and replaces the doc.
  defp push_editor_content(socket, elements) do
    client_elements =
      Enum.map(elements, fn el ->
        %{
          id: el.id,
          type: el.type,
          position: el.position,
          content: el.content || "",
          data: el.data || %{}
        }
      end)

    push_event(socket, "set_editor_content", %{elements: client_elements})
  end

  # Push element data back to TipTap NodeViews after server-side mutations
  defp push_element_data_updated(socket, %{id: id, data: data}) do
    push_event(socket, "element_data_updated", %{element_id: id, data: data || %{}})
  end

  defp update_choice_field(socket, element_id, choice_id, update_fn) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_choice_update(socket, element, choice_id, update_fn)
    end
  end

  defp persist_choice_update(socket, element, choice_id, update_fn) do
    data = element.data || %{}

    choices =
      Enum.map(data["choices"] || [], fn choice ->
        if choice["id"] == choice_id, do: update_fn.(choice), else: choice
      end)

    data = Map.put(data, "choices", choices)

    case Screenplays.update_element(element, %{data: data}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> update_element_in_list(updated)
         |> push_element_data_updated(updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not update choice."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Data sanitization — type-aware sanitization for sync_editor_content
  # ---------------------------------------------------------------------------

  defp sanitize_element_data("conditional", data) when is_map(data) do
    %{"condition" => Condition.sanitize(data["condition"])}
  end

  defp sanitize_element_data("instruction", data) when is_map(data) do
    %{"assignments" => Instruction.sanitize(data["assignments"])}
  end

  defp sanitize_element_data("response", data) when is_map(data) do
    choices =
      (data["choices"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn choice ->
        choice
        |> Map.take(~w(id text condition instruction linked_screenplay_id))
        |> sanitize_choice_fields()
      end)

    %{"choices" => choices}
  end

  defp sanitize_element_data("title_page", data) when is_map(data) do
    data
    |> Map.take(@valid_title_fields)
    |> Map.new(fn {k, v} -> {k, sanitize_plain_text(v)} end)
  end

  defp sanitize_element_data("dual_dialogue", data) when is_map(data) do
    Map.new(@valid_dual_sides, fn side ->
      side_data = data[side] || %{}

      sanitized =
        side_data
        |> Map.take(@valid_dual_fields)
        |> Map.new(fn
          {"dialogue", v} -> {"dialogue", ContentUtils.sanitize_html(v)}
          {"parenthetical", v} -> {"parenthetical", ContentUtils.sanitize_html(v)}
          {"character", v} -> {"character", sanitize_plain_text(v)}
        end)

      {side, sanitized}
    end)
  end

  defp sanitize_element_data("character", data) when is_map(data) do
    case data["sheet_id"] do
      nil -> %{}
      sheet_id -> %{"sheet_id" => sheet_id}
    end
  end

  defp sanitize_element_data(_type, _data), do: %{}

  defp sanitize_choice_fields(choice) do
    choice
    |> update_if_present("text", &sanitize_plain_text/1)
    |> update_if_present("condition", &Condition.sanitize/1)
    |> update_if_present("instruction", &Instruction.sanitize/1)
  end

  defp update_if_present(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp sanitize_plain_text(value) when is_binary(value), do: ContentUtils.strip_html(value)
  defp sanitize_plain_text(_), do: ""

  defp screenplay_translations do
    Map.merge(InstructionBuilder.translations(), ConditionBuilder.translations())
  end
end
