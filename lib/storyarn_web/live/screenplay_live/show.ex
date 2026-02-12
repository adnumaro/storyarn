defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Flows
  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.ElementGrouping
  alias Storyarn.Screenplays.FlowSync
  alias Storyarn.Screenplays.LinkedPageCrud
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Sheets

  import StoryarnWeb.Components.Screenplay.ElementRenderer
  import StoryarnWeb.Components.Screenplay.SlashCommandMenu

  # Standard types eligible for auto-detection on content update
  @auto_detect_types ~w(action scene_heading character dialogue parenthetical transition)

  # Dual dialogue field validation
  @valid_dual_sides ~w(left right)
  @valid_dual_fields ~w(character parenthetical dialogue)

  # Types hidden in read mode (interactive, utility, and stub blocks)
  @read_mode_hidden_types ~w(conditional instruction response note hub_marker jump_marker title_page)

  # Server-side next-type inference (Enter key creates the logical next element).
  # Note/section types are excluded intentionally — Enter always creates "action" for them.
  @next_type %{
    "scene_heading" => "action",
    "action" => "action",
    "character" => "dialogue",
    "parenthetical" => "dialogue",
    "dialogue" => "action",
    "transition" => "scene_heading"
  }

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
      <div class="screenplay-toolbar" id="screenplay-toolbar">
        <div class="screenplay-toolbar-left">
          <h1
            :if={@can_edit}
            id="screenplay-title"
            class="screenplay-toolbar-title"
            contenteditable="true"
            phx-hook="EditableTitle"
            phx-update="ignore"
            data-placeholder={gettext("Untitled")}
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
            {ngettext("%{count} element", "%{count} elements", length(@elements))}
          </span>
          <span :if={Screenplay.draft?(@screenplay)} class="screenplay-toolbar-badge screenplay-toolbar-draft">
            {gettext("Draft")}
          </span>
          <button
            type="button"
            class={["sp-toolbar-btn", @read_mode && "sp-toolbar-btn-active"]}
            phx-click="toggle_read_mode"
            title={if @read_mode, do: gettext("Exit read mode"), else: gettext("Read mode")}
          >
            <.icon name={if @read_mode, do: "pencil", else: "book-open"} class="size-4" />
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
                {gettext("Create Flow")}
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
                title={gettext("Push screenplay to flow")}
              >
                <.icon name="upload" class="size-3.5" />
                {gettext("To Flow")}
              </button>
              <button
                :if={@can_edit}
                class="sp-sync-btn"
                phx-click="sync_from_flow"
                title={gettext("Update screenplay from flow")}
              >
                <.icon name="download" class="size-3.5" />
                {gettext("From Flow")}
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
                {if status == :flow_deleted, do: gettext("Flow trashed"), else: gettext("Flow missing")}
              </span>
              <button
                :if={@can_edit}
                class="sp-sync-btn sp-sync-btn-subtle"
                phx-click="unlink_flow"
              >
                <.icon name="unlink" class="size-3.5" />
                {gettext("Unlink")}
              </button>
          <% end %>
        </div>
      </div>
      <div
        id="screenplay-page"
        class={["screenplay-page", @read_mode && "screenplay-read-mode"]}
        phx-hook="ScreenplayEditorPage"
      >
        <div
          :if={@elements == [] && !@read_mode}
          class="screenplay-element sp-action sp-empty sp-empty-state"
          phx-click={@can_edit && "create_first_element"}
        >
          <div class="sp-block" data-placeholder={gettext("Start typing or press / for commands")}></div>
        </div>
        <.element_renderer
          :for={element <- visible_elements(@elements, @read_mode)}
          element={element}
          can_edit={@can_edit && !@read_mode}
          variables={@project_variables}
          linked_pages={@linked_pages}
          continuations={@continuations}
        />
      </div>
      <.slash_command_menu
        :if={@slash_menu_element_id && !@read_mode}
        element_id={@slash_menu_element_id}
      />
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
        screenplays_tree = Screenplays.list_screenplays_tree(project.id)
        elements = Screenplays.list_elements(screenplay.id)
        project_variables = Sheets.list_project_variables(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)
        {link_status, linked_flow} = detect_link_status(screenplay)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:screenplay, screenplay)
          |> assign(:screenplays_tree, screenplays_tree)
          |> assign_elements_with_continuations(elements)
          |> assign(:project_variables, project_variables)
          |> assign(:slash_menu_element_id, nil)
          |> assign(:read_mode, false)
          |> assign(:link_status, link_status)
          |> assign(:linked_flow, linked_flow)
          |> assign(:linked_pages, load_linked_pages(screenplay))

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  # ---------------------------------------------------------------------------
  # Read mode
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_read_mode", _params, socket) do
    {:noreply, assign(socket, :read_mode, !socket.assigns.read_mode)}
  end

  # ---------------------------------------------------------------------------
  # Element editing handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_element_content", %{"id" => id, "content" => content}, socket) do
    with_edit_permission(socket, fn ->
      do_update_element_content(socket, id, content)
    end)
  end

  def handle_event(
        "create_next_element",
        %{"after_id" => after_id, "content" => content},
        socket
      ) do
    with_edit_permission(socket, fn ->
      do_create_next_element(socket, after_id, content)
    end)
  end

  def handle_event("create_first_element", _params, socket) do
    with_edit_permission(socket, fn ->
      attrs = %{type: "action", content: ""}

      case Screenplays.insert_element_at(socket.assigns.screenplay, 0, attrs) do
        {:ok, new_element} ->
          elements = Screenplays.list_elements(socket.assigns.screenplay.id)

          {:noreply,
           socket
           |> assign_elements_with_continuations(elements)
           |> push_event("focus_element", %{id: new_element.id})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create element."))}
      end
    end)
  end

  def handle_event("delete_element", %{"id" => id}, socket) do
    with_edit_permission(socket, fn ->
      do_delete_element(socket, id)
    end)
  end

  def handle_event("change_element_type", %{"id" => id, "type" => type}, socket) do
    with_edit_permission(socket, fn ->
      do_change_element_type(socket, id, type)
    end)
  end

  # ---------------------------------------------------------------------------
  # Slash command handlers
  # ---------------------------------------------------------------------------

  def handle_event("open_slash_menu", %{"element_id" => id}, socket) do
    with_edit_permission(socket, fn ->
      case find_element(socket, id) do
        nil ->
          {:noreply, socket}

        element ->
          {:noreply, assign(socket, :slash_menu_element_id, element.id)}
      end
    end)
  end

  def handle_event("select_slash_command", %{"type" => type}, socket) do
    with_edit_permission(socket, fn ->
      do_select_slash_command(socket, type)
    end)
  end

  def handle_event("split_and_open_slash_menu", params, socket) do
    %{"element_id" => id, "cursor_position" => pos} = params
    pos = if is_integer(pos), do: pos, else: parse_int(pos)

    with_edit_permission(socket, fn ->
      do_split_and_open_slash_menu(socket, id, pos)
    end)
  end

  def handle_event("close_slash_menu", _params, socket) do
    element_id = socket.assigns.slash_menu_element_id

    socket =
      socket
      |> assign(:slash_menu_element_id, nil)

    socket =
      if element_id do
        push_event(socket, "focus_element", %{id: element_id})
      else
        socket
      end

    {:noreply, socket}
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
          {:noreply, put_flash(socket, :error, gettext("Could not save screenplay name."))}
      end
    end)
  end

  def handle_event("create_flow_from_screenplay", _params, socket) do
    with_edit_permission(socket, fn ->
      screenplay = socket.assigns.screenplay

      with {:ok, flow} <- FlowSync.ensure_flow(screenplay),
           screenplay = Screenplays.get_screenplay!(screenplay.project_id, screenplay.id),
           {:ok, _flow} <- FlowSync.sync_to_flow(screenplay) do
        screenplay = Screenplays.get_screenplay!(screenplay.project_id, screenplay.id)

        {:noreply,
         socket
         |> assign(:screenplay, screenplay)
         |> assign(:link_status, :linked)
         |> assign(:linked_flow, flow)
         |> put_flash(:info, gettext("Flow created and synced."))}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create flow."))}
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

      case FlowSync.unlink_flow(screenplay) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:screenplay, updated)
           |> assign(:link_status, :unlinked)
           |> assign(:linked_flow, nil)
           |> put_flash(:info, gettext("Flow unlinked."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not unlink flow."))}
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

  defp do_update_element_content(socket, id, content) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        attrs = build_update_attrs(element, content)
        persist_element_content(socket, element, attrs)
    end
  end

  defp persist_element_content(socket, element, attrs) do
    case Screenplays.update_element(element, attrs) do
      {:ok, updated} ->
        socket = update_element_in_list(socket, updated)

        socket =
          if updated.type != element.type,
            do: push_event(socket, "element_type_changed", %{id: updated.id, type: updated.type}),
            else: socket

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save content."))}
    end
  end

  defp do_create_next_element(socket, after_id, content) do
    case find_element(socket, after_id) do
      nil ->
        {:noreply, socket}

      element ->
        new_position = element.position + 1
        next_type = Map.get(@next_type, element.type, "action")
        attrs = %{type: next_type, content: content}

        case Screenplays.insert_element_at(
               socket.assigns.screenplay,
               new_position,
               attrs
             ) do
          {:ok, new_element} ->
            elements = Screenplays.list_elements(socket.assigns.screenplay.id)

            {:noreply,
             socket
             |> assign_elements_with_continuations(elements)
             |> push_event("focus_element", %{id: new_element.id})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create element."))}
        end
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
    case Screenplays.delete_element(element) do
      {:ok, _} ->
        reloaded = Screenplays.list_elements(socket.assigns.screenplay.id)

        socket = assign_elements_with_continuations(socket, reloaded)

        socket =
          if prev do
            push_event(socket, "focus_element", %{id: prev.id})
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete element."))}
    end
  end

  defp do_change_element_type(socket, id, type) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        case Screenplays.update_element(element, %{type: type}) do
          {:ok, updated} ->
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not change element type."))}
        end
    end
  end

  defp do_select_slash_command(socket, type) do
    element_id = socket.assigns.slash_menu_element_id
    element = element_id && Enum.find(socket.assigns.elements, &(&1.id == element_id))

    cond do
      is_nil(element_id) ->
        {:noreply, socket}

      is_nil(element) || type not in ScreenplayElement.types() ->
        {:noreply, assign(socket, :slash_menu_element_id, nil)}

      true ->
        apply_slash_command(socket, element, type)
    end
  end

  defp apply_slash_command(socket, element, type) do
    case Screenplays.update_element(element, slash_command_attrs(type)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> update_element_in_list(updated)
         |> assign(:slash_menu_element_id, nil)
         |> push_event("focus_element", %{id: updated.id})}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:slash_menu_element_id, nil)
         |> put_flash(:error, gettext("Could not change element type."))}
    end
  end

  defp slash_command_attrs("dual_dialogue") do
    %{
      type: "dual_dialogue",
      content: "",
      data: %{
        "left" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""},
        "right" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""}
      }
    }
  end

  defp slash_command_attrs(type), do: %{type: type}

  defp do_update_dual_dialogue(socket, id, side, field, value)
       when side in @valid_dual_sides and field in @valid_dual_fields do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        data = element.data || %{}
        side_data = data[side] || %{}
        updated_side = Map.put(side_data, field, value)
        updated_data = Map.put(data, side, updated_side)

        case Screenplays.update_element(element, %{data: updated_data}) do
          {:ok, updated} ->
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not update dual dialogue."))}
        end
    end
  end

  defp do_update_dual_dialogue(socket, _id, _side, _field, _value), do: {:noreply, socket}

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
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not toggle parenthetical."))}
        end
    end
  end

  defp do_toggle_dual_parenthetical(socket, _id, _side), do: {:noreply, socket}

  defp do_split_and_open_slash_menu(socket, id, pos) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      _element when is_nil(pos) ->
        {:noreply, socket}

      element ->
        case Screenplays.split_element(element, pos, "action") do
          {:ok, {_before, new_element, _after}} ->
            elements = Screenplays.list_elements(socket.assigns.screenplay.id)

            {:noreply,
             socket
             |> assign_elements_with_continuations(elements)
             |> assign(:slash_menu_element_id, new_element.id)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not split element."))}
        end
    end
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
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not save condition."))}
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
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not save instruction."))}
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
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not add choice."))}
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
            {:noreply, update_element_in_list(socket, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not remove choice."))}
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

  defp do_sync_to_flow(socket) do
    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, gettext("Screenplay is not linked to a flow."))}
    else
      case FlowSync.sync_to_flow(socket.assigns.screenplay) do
        {:ok, _flow} ->
          {:noreply, put_flash(socket, :info, gettext("Screenplay synced to flow."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not sync screenplay."))}
      end
    end
  end

  defp do_sync_from_flow(socket) do
    screenplay = socket.assigns.screenplay

    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, gettext("Screenplay is not linked to a flow."))}
    else
      case FlowSync.sync_from_flow(screenplay) do
        {:ok, _screenplay} ->
          elements = Screenplays.list_elements(screenplay.id)

          {:noreply,
           socket
           |> assign_elements_with_continuations(elements)
           |> put_flash(:info, gettext("Screenplay updated from flow."))}

        {:error, :no_entry_node} ->
          {:noreply, put_flash(socket, :error, gettext("Flow has no entry node."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not sync from flow."))}
      end
    end
  end

  defp do_delete_screenplay(socket, screenplay_id) do
    case Screenplays.get_screenplay(socket.assigns.project.id, screenplay_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Screenplay not found."))}

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
           |> put_flash(:info, gettext("Screenplay moved to trash."))
           |> push_navigate(to: screenplays_path(socket))}
        else
          {:noreply,
           socket
           |> put_flash(:info, gettext("Screenplay moved to trash."))
           |> reload_screenplays_tree()}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete screenplay."))}
    end
  end

  defp do_move_to_parent(socket, item_id, new_parent_id, position) do
    case Screenplays.get_screenplay(socket.assigns.project.id, item_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Screenplay not found."))}

      screenplay ->
        new_parent_id = parse_int(new_parent_id)
        position = parse_int(position) || 0

        case Screenplays.move_screenplay_to_position(screenplay, new_parent_id, position) do
          {:ok, _} ->
            {:noreply, reload_screenplays_tree(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not move screenplay."))}
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
            {:noreply,
             socket
             |> update_element_in_list(updated_element)
             |> assign(:linked_pages, load_linked_pages(screenplay))
             |> reload_screenplays_tree()
             |> put_flash(:info, gettext("Linked page created."))}

          {:error, :choice_not_found} ->
            {:noreply, put_flash(socket, :error, gettext("Choice not found."))}

          {:error, :already_linked} ->
            {:noreply, put_flash(socket, :error, gettext("Choice already has a linked page."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create linked page."))}
        end
    end
  end

  defp do_navigate_to_linked_page(socket, element_id, choice_id) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        choice = LinkedPageCrud.find_choice(element, choice_id)
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
            {:noreply, update_element_in_list(socket, updated_element)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not unlink choice."))}
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
            {:noreply,
             socket
             |> update_element_in_list(updated_element)
             |> assign(:linked_pages, load_linked_pages(screenplay))
             |> reload_screenplays_tree()
             |> put_flash(:info, gettext("Linked pages created."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create linked pages."))}
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

  defp visible_elements(elements, false), do: elements

  defp visible_elements(elements, true) do
    Enum.reject(elements, &(&1.type in @read_mode_hidden_types))
  end

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
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp do_create_screenplay(socket, extra_attrs) do
    with_edit_permission(socket, fn ->
      attrs = Map.merge(%{name: gettext("Untitled")}, extra_attrs)

      case Screenplays.create_screenplay(socket.assigns.project, attrs) do
        {:ok, new_screenplay} ->
          {:noreply, push_navigate(socket, to: screenplays_path(socket, new_screenplay.id))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create screenplay."))}
      end
    end)
  end

  defp build_update_attrs(element, content) do
    base = %{content: content}

    if element.type in @auto_detect_types do
      case Screenplays.detect_type(content) do
        nil -> base
        detected when detected == element.type -> base
        detected -> Map.put(base, :type, detected)
      end
    else
      base
    end
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

    assign_elements_with_continuations(socket, elements)
  end

  defp assign_elements_with_continuations(socket, elements) do
    socket
    |> assign(:elements, elements)
    |> assign(:continuations, ElementGrouping.compute_continuations(elements))
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
        {:noreply, update_element_in_list(socket, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update choice."))}
    end
  end
end
