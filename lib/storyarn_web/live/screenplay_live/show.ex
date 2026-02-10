defmodule StoryarnWeb.ScreenplayLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Projects
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Screenplays.FlowSync
  alias Storyarn.Flows
  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Sheets
  alias Storyarn.Repo

  import StoryarnWeb.Components.Screenplay.ElementRenderer
  import StoryarnWeb.Components.Screenplay.SlashCommandMenu

  # Standard types eligible for auto-detection on content update
  @auto_detect_types ~w(action scene_heading character dialogue parenthetical transition)

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
              >
                <.icon name="refresh-cw" class="size-3.5" />
                {gettext("Sync")}
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
      <div id="screenplay-page" class="screenplay-page" phx-hook="ScreenplayEditorPage">
        <div
          :if={@elements == []}
          class="screenplay-element sp-action sp-empty sp-empty-state"
          phx-click={@can_edit && "create_first_element"}
        >
          <div class="sp-block" data-placeholder={gettext("Start typing or press / for commands")}></div>
        </div>
        <.element_renderer
          :for={element <- @elements}
          element={element}
          can_edit={@can_edit}
          variables={@project_variables}
        />
      </div>
      <.slash_command_menu
        :if={@slash_menu_element_id}
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
          |> assign(:elements, elements)
          |> assign(:project_variables, project_variables)
          |> assign(:slash_menu_element_id, nil)
          |> assign(:link_status, link_status)
          |> assign(:linked_flow, linked_flow)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  # ---------------------------------------------------------------------------
  # Element editing handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_element_content", %{"id" => id, "content" => content}, socket) do
    with_edit_permission(socket, fn ->
      case find_element(socket, id) do
        nil ->
          {:noreply, socket}

        element ->
          attrs = build_update_attrs(element, content)

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
    end)
  end

  def handle_event(
        "create_next_element",
        %{"after_id" => after_id, "content" => content},
        socket
      ) do
    with_edit_permission(socket, fn ->
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
               |> assign(:elements, elements)
               |> push_event("focus_element", %{id: new_element.id})}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, gettext("Could not create element."))}
          end
      end
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
           |> assign(:elements, elements)
           |> push_event("focus_element", %{id: new_element.id})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create element."))}
      end
    end)
  end

  def handle_event("delete_element", %{"id" => id}, socket) do
    with_edit_permission(socket, fn ->
      case find_element(socket, id) do
        nil ->
          {:noreply, socket}

        element ->
          elements = socket.assigns.elements
          prev = Enum.find(elements, &(&1.position == element.position - 1))

          case Screenplays.delete_element(element) do
            {:ok, _} ->
              reloaded = Screenplays.list_elements(socket.assigns.screenplay.id)

              socket = assign(socket, :elements, reloaded)

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
    end)
  end

  def handle_event("change_element_type", %{"id" => id, "type" => type}, socket) do
    with_edit_permission(socket, fn ->
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
      element_id = socket.assigns.slash_menu_element_id

      if is_nil(element_id) do
        {:noreply, socket}
      else
        element = Enum.find(socket.assigns.elements, &(&1.id == element_id))

        if is_nil(element) || type not in ScreenplayElement.types() do
          {:noreply, assign(socket, :slash_menu_element_id, nil)}
        else
          case Screenplays.update_element(element, %{type: type}) do
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
      end
    end)
  end

  def handle_event("split_and_open_slash_menu", params, socket) do
    %{"element_id" => id, "cursor_position" => pos} = params
    pos = if is_integer(pos), do: pos, else: parse_int(pos)

    with_edit_permission(socket, fn ->
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
               |> assign(:elements, elements)
               |> assign(:slash_menu_element_id, new_element.id)}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, gettext("Could not split element."))}
          end
      end
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
    end)
  end

  def handle_event(
        "update_screenplay_instruction",
        %{"element-id" => id, "assignments" => assignments},
        socket
      ) do
    with_edit_permission(socket, fn ->
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
    end)
  end

  def handle_event("add_response_choice", %{"element-id" => id}, socket) do
    with_edit_permission(socket, fn ->
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
    end)
  end

  def handle_event(
        "remove_response_choice",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
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
    end)
  end

  def handle_event(
        "update_response_choice_text",
        %{"element-id" => id, "choice-id" => choice_id, "value" => text},
        socket
      ) do
    with_edit_permission(socket, fn ->
      case find_element(socket, id) do
        nil ->
          {:noreply, socket}

        element ->
          data = element.data || %{}

          choices =
            Enum.map(data["choices"] || [], fn choice ->
              if choice["id"] == choice_id, do: Map.put(choice, "text", text), else: choice
            end)

          data = Map.put(data, "choices", choices)

          case Screenplays.update_element(element, %{data: data}) do
            {:ok, updated} ->
              {:noreply, update_element_in_list(socket, updated)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, gettext("Could not update choice."))}
          end
      end
    end)
  end

  def handle_event(
        "toggle_choice_condition",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
      update_choice_field(socket, id, choice_id, fn choice ->
        if choice["condition"],
          do: Map.delete(choice, "condition"),
          else: Map.put(choice, "condition", Condition.new())
      end)
    end)
  end

  def handle_event(
        "toggle_choice_instruction",
        %{"element-id" => id, "choice-id" => choice_id},
        socket
      ) do
    with_edit_permission(socket, fn ->
      update_choice_field(socket, id, choice_id, fn choice ->
        if choice["instruction"],
          do: Map.delete(choice, "instruction"),
          else: Map.put(choice, "instruction", [])
      end)
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
      screenplay = socket.assigns.screenplay

      if socket.assigns.link_status != :linked do
        {:noreply, put_flash(socket, :error, gettext("Screenplay is not linked to a flow."))}
      else
        case FlowSync.sync_to_flow(screenplay) do
          {:ok, _flow} ->
            {:noreply, put_flash(socket, :info, gettext("Screenplay synced to flow."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not sync screenplay."))}
        end
      end
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
      case Screenplays.get_screenplay(socket.assigns.project.id, screenplay_id) do
        nil ->
          {:noreply, put_flash(socket, :error, gettext("Screenplay not found."))}

        screenplay ->
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
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
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

    assign(socket, :elements, elements)
  end

  defp update_choice_field(socket, element_id, choice_id, update_fn) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
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
end
