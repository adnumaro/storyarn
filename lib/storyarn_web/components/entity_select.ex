defmodule StoryarnWeb.Components.EntitySelect do
  @moduledoc """
  Thin wrapper around `SearchableSelect` for selecting project entities.

  Normalizes `entity_type` / `entity_types` into MFA tuples and delegates all
  search, pagination, and rendering logic to `SearchableSelect`.

  ## Communication

      send(self(), {:entity_selected, component_id, selected_id_or_nil})

  ## Usage

      # Single type (backward compatible)
      <.live_component
        module={EntitySelect}
        id="pin-sheet-123"
        project_id={@project.id}
        entity_type={:sheet}
        selected_id={@pin.sheet_id}
        label={dgettext("scenes", "Sheet")}
        placeholder={dgettext("scenes", "Select sheet...")}
        disabled={!@can_edit}
      />

      # Multi-type
      <.live_component
        module={EntitySelect}
        id="reference-123"
        project_id={@project.id}
        entity_types={[:sheet, :flow]}
        selected_id={@ref_id}
        label="Reference"
      />
  """

  use StoryarnWeb, :live_component
  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Components.SearchableSelect
  alias StoryarnWeb.Helpers.EntitySearch

  @impl true
  def update(assigns, socket) do
    types = assigns[:entity_types] || [assigns[:entity_type]]

    {search_fn, get_name_fn} = build_mfa_tuples(types, assigns.project_id)

    {:ok, assign(socket, Map.merge(assigns, %{search_fn: search_fn, get_name_fn: get_name_fn}))}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:allow_none, fn -> true end)
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> gettext("Select...") end)
      |> assign_new(:search_placeholder, fn -> search_placeholder(assigns) end)

    ~H"""
    <div>
      <.live_component
        module={SearchableSelect}
        id={"#{@id}-inner"}
        search_fn={@search_fn}
        get_name_fn={@get_name_fn}
        value={@selected_id}
        on_select="entity_selected"
        target={@myself}
        label={@label}
        placeholder={@placeholder}
        search_placeholder={@search_placeholder}
        allow_none={@allow_none}
        disabled={@disabled}
      />
    </div>
    """
  end

  @impl true
  def handle_event("entity_selected", %{"id" => id}, socket) do
    parsed_id = if id == "", do: nil, else: parse_id(id)
    send(self(), {:entity_selected, socket.assigns.id, parsed_id})
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_mfa_tuples([type], project_id) do
    {
      {EntitySearch, :search_entities, [type, project_id]},
      {EntitySearch, :get_entity_name, [type, project_id]}
    }
  end

  defp build_mfa_tuples(types, project_id) when is_list(types) do
    {
      {EntitySearch, :search_entities_multi, [types, project_id]},
      {EntitySearch, :get_entity_name_multi, [types, project_id]}
    }
  end

  defp search_placeholder(%{entity_types: types}) when is_list(types) do
    gettext("Search...")
  end

  defp search_placeholder(%{entity_type: :sheet}), do: dgettext("scenes", "Search sheets...")
  defp search_placeholder(%{entity_type: :flow}), do: dgettext("scenes", "Search flows...")
  defp search_placeholder(%{entity_type: :scene}), do: dgettext("scenes", "Search scenes...")
  defp search_placeholder(_), do: gettext("Search...")

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp parse_id(value), do: value
end
