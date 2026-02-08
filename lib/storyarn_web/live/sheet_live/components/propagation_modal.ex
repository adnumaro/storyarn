defmodule StoryarnWeb.SheetLive.Components.PropagationModal do
  @moduledoc """
  LiveComponent for the property propagation modal.

  Shows a tree of descendant sheets with checkboxes, allowing the user
  to select which sheets should receive the inherited property.
  """

  use StoryarnWeb, :live_component

  import Ecto.Query, warn: false

  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-lg">
        <h3 class="font-bold text-lg">
          {gettext("Propagate \"%{name}\" to existing children?",
            name: @block.config["label"] || @block.type
          )}
        </h3>

        <p class="py-2 text-sm text-base-content/70">
          {gettext(
            "This property will automatically appear in all new children. For existing children:"
          )}
        </p>

        <%!-- Select all toggle --%>
        <label class="flex items-center gap-2 cursor-pointer py-2 border-b border-base-300 mb-2">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            checked={@all_selected}
            phx-click="toggle_all"
            phx-target={@myself}
          />
          <span class="font-medium text-sm">
            {gettext("Select all (%{count} pages)", count: length(@descendants))}
          </span>
        </label>

        <%!-- Descendants tree --%>
        <div class="max-h-64 overflow-y-auto py-2">
          <.descendant_tree
            descendants={@tree}
            selected_ids={@selected_ids}
            target={@myself}
            depth={0}
          />
        </div>

        <p class="text-xs text-base-content/50 mt-2">
          {gettext("Unselected pages won't get this property but can add it manually later.")}
        </p>

        <%!-- Actions --%>
        <div class="modal-action">
          <button type="button" class="btn btn-ghost" phx-click="cancel_propagation" phx-target={@target}>
            {gettext("Cancel")}
          </button>
          <button
            type="button"
            class="btn btn-primary"
            phx-click="propagate_property"
            phx-value-sheet_ids={Jason.encode!(@selected_ids)}
            phx-target={@target}
            disabled={@selected_ids == []}
          >
            {gettext("Propagate")}
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_propagation" phx-target={@target}></div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    sheet = assigns.sheet

    # Get all descendants as a flat list and as a tree
    descendants = get_flat_descendants(sheet.id)
    tree = get_descendant_tree(sheet.id)
    all_ids = Enum.map(descendants, & &1.id)

    socket =
      socket
      |> assign(assigns)
      |> assign(:descendants, descendants)
      |> assign(:tree, tree)
      |> assign_new(:selected_ids, fn -> all_ids end)

    # Compute all_selected AFTER selected_ids is set (may have been preserved from previous render)
    selected_ids = socket.assigns.selected_ids
    socket = assign(socket, :all_selected, length(selected_ids) == length(all_ids) and all_ids != [])

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.descendants, & &1.id)

    selected_ids =
      if socket.assigns.all_selected do
        []
      else
        all_ids
      end

    {:noreply,
     socket
     |> assign(:selected_ids, selected_ids)
     |> assign(:all_selected, selected_ids == all_ids)}
  end

  def handle_event("toggle_descendant", %{"id" => id}, socket) do
    id =
      case Integer.parse(id) do
        {int_id, _} -> int_id
        :error -> nil
      end

    if is_nil(id) do
      {:noreply, socket}
    else
      selected = socket.assigns.selected_ids
      all_ids = Enum.map(socket.assigns.descendants, & &1.id)

      selected =
        if id in selected do
          List.delete(selected, id)
        else
          [id | selected]
        end

      {:noreply,
       socket
       |> assign(:selected_ids, selected)
       |> assign(:all_selected, length(selected) == length(all_ids))}
    end
  end

  # ===========================================================================
  # Sub-components
  # ===========================================================================

  attr :descendants, :list, required: true
  attr :selected_ids, :list, required: true
  attr :target, :any, required: true
  attr :depth, :integer, default: 0

  defp descendant_tree(assigns) do
    ~H"""
    <div :for={node <- @descendants} style={"padding-left: #{@depth * 16}px"}>
      <label class="flex items-center gap-2 cursor-pointer py-1 hover:bg-base-200 rounded px-2">
        <input
          type="checkbox"
          class="checkbox checkbox-sm"
          checked={node.id in @selected_ids}
          phx-click="toggle_descendant"
          phx-value-id={node.id}
          phx-target={@target}
        />
        <span class="text-sm">{node.name}</span>
      </label>
      <.descendant_tree
        :if={node.children != []}
        descendants={node.children}
        selected_ids={@selected_ids}
        target={@target}
        depth={@depth + 1}
      />
    </div>
    """
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_flat_descendants(sheet_id) do
    ids = Sheets.get_descendant_sheet_ids(sheet_id)

    if ids == [] do
      []
    else
      Storyarn.Sheets.Sheet
      |> where([s], s.id in ^ids and is_nil(s.deleted_at))
      |> order_by([s], [asc: s.position, asc: s.name])
      |> Storyarn.Repo.all()
    end
  end

  defp get_descendant_tree(sheet_id) do
    direct_children =
      Storyarn.Sheets.Sheet
      |> where([s], s.parent_id == ^sheet_id and is_nil(s.deleted_at))
      |> order_by([s], [asc: s.position, asc: s.name])
      |> Storyarn.Repo.all()

    Enum.map(direct_children, fn child ->
      children = get_descendant_tree(child.id)
      %{id: child.id, name: child.name, children: children}
    end)
  end
end
