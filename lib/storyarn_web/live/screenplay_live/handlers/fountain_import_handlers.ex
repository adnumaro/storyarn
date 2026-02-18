defmodule StoryarnWeb.ScreenplayLive.Handlers.FountainImportHandlers do
  @moduledoc """
  Fountain import handlers for the screenplay LiveView.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.CharacterExtension
  alias Storyarn.Sheets

  import StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers

  def do_import_fountain(socket, content) when is_binary(content) do
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

  def do_import_fountain(socket, _content), do: {:noreply, socket}

  defp delete_all_elements(elements) do
    result =
      Enum.reduce_while(elements, :ok, fn el, _ ->
        Sheets.delete_screenplay_element_references(el.id)

        case Screenplays.delete_element(el) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      :ok -> {:ok, :deleted}
      error -> error
    end
  end

  defp create_elements_from_parsed(screenplay, parsed) do
    result =
      Enum.reduce_while(parsed, {:ok, []}, fn attrs, {:ok, acc} ->
        case Screenplays.create_element(screenplay, attrs) do
          {:ok, el} -> {:cont, {:ok, [el | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, elements} -> {:ok, Enum.reverse(elements)}
      error -> error
    end
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
    Phoenix.Component.assign(socket, :sheets_map, Map.new(all_sheets, &{&1.id, &1}))
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
end
