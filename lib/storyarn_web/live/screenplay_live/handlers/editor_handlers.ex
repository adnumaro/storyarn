defmodule StoryarnWeb.ScreenplayLive.Handlers.EditorHandlers do
  @moduledoc """
  Editor content sync handlers for the screenplay LiveView.
  """

  require Logger

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias Storyarn.Screenplays
  alias Storyarn.Sheets

  alias StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers
  import SocketHelpers

  # All types managed by the unified TipTap editor (text blocks + atom NodeViews)
  @editor_types ~w(scene_heading action character dialogue parenthetical transition note section page_break hub_marker jump_marker title_page conditional instruction response dual_dialogue)

  # Title page / dual dialogue field validation (canonical source: SocketHelpers)
  @valid_title_fields SocketHelpers.valid_title_fields()
  @valid_dual_sides SocketHelpers.valid_dual_sides()
  @valid_dual_fields SocketHelpers.valid_dual_fields()

  def do_sync_editor_content(socket, client_elements) when is_list(client_elements) do
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

  def do_sync_editor_content(socket, _), do: {:noreply, socket}

  def extract_client_ids(client_elements) do
    client_elements
    |> Enum.map(& &1["element_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  def delete_removed_editor_elements(existing, client_ids) do
    existing
    |> Enum.filter(&(&1.type in @editor_types))
    |> Enum.reject(&(&1.id in client_ids))
    |> Enum.each(fn el ->
      Sheets.delete_screenplay_element_references(el.id)
      Screenplays.delete_element(el)
    end)
  end

  def upsert_client_elements(screenplay, client_elements, existing_by_id) do
    {ordered_ids, changed_ids} =
      Enum.reduce(client_elements, {[], MapSet.new()}, fn el, {ids, changed} ->
        element_id = el["element_id"] && parse_int(el["element_id"])

        type = el["type"] || "action"

        attrs = %{
          type: type,
          content: Screenplays.content_sanitize_html(el["content"]),
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

  def upsert_single_element(screenplay, attrs, nil) do
    case Screenplays.create_element(screenplay, attrs) do
      {:ok, created} -> {:created, created.id}
      _ -> :error
    end
  end

  def upsert_single_element(_screenplay, attrs, existing_el) do
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

  def reorder_after_sync(screenplay, ordered_ids) do
    if ordered_ids != [] do
      Screenplays.reorder_elements(screenplay.id, ordered_ids)
    end
  end

  # ---------------------------------------------------------------------------
  # Data sanitization — type-aware sanitization for sync_editor_content
  # ---------------------------------------------------------------------------

  def sanitize_element_data("conditional", data) when is_map(data) do
    %{"condition" => Flows.condition_sanitize(data["condition"])}
  end

  def sanitize_element_data("instruction", data) when is_map(data) do
    %{"assignments" => Flows.instruction_sanitize(data["assignments"])}
  end

  def sanitize_element_data("response", data) when is_map(data) do
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

  def sanitize_element_data("title_page", data) when is_map(data) do
    data
    |> Map.take(@valid_title_fields)
    |> Map.new(fn {k, v} -> {k, sanitize_plain_text(v)} end)
  end

  def sanitize_element_data("dual_dialogue", data) when is_map(data) do
    Map.new(@valid_dual_sides, fn side ->
      side_data = data[side] || %{}

      sanitized =
        side_data
        |> Map.take(@valid_dual_fields)
        |> Map.new(fn
          {"dialogue", v} -> {"dialogue", Screenplays.content_sanitize_html(v)}
          {"parenthetical", v} -> {"parenthetical", Screenplays.content_sanitize_html(v)}
          {"character", v} -> {"character", sanitize_plain_text(v)}
        end)

      {side, sanitized}
    end)
  end

  def sanitize_element_data("character", data) when is_map(data) do
    case data["sheet_id"] do
      nil -> %{}
      sheet_id -> %{"sheet_id" => sheet_id}
    end
  end

  def sanitize_element_data(_type, _data), do: %{}

  def sanitize_choice_fields(choice) do
    choice
    |> update_if_present("text", &sanitize_plain_text/1)
    |> update_if_present("condition", &Flows.condition_sanitize/1)
    |> update_if_present("instruction", &Flows.instruction_sanitize/1)
  end

  def update_if_present(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end
end
