defmodule StoryarnWeb.ScreenplayLive.Handlers.ElementHandlers do
  @moduledoc """
  Element CRUD and mutation handlers for the screenplay LiveView.
  """

  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.Instruction
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.ContentUtils
  alias Storyarn.Sheets

  alias StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers
  import SocketHelpers

  # Title page / dual dialogue field validation (canonical source: SocketHelpers)
  @valid_dual_sides SocketHelpers.valid_dual_sides()
  @valid_dual_fields SocketHelpers.valid_dual_fields()
  @valid_title_fields SocketHelpers.valid_title_fields()

  def do_delete_element(socket, id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        prev = Enum.find(socket.assigns.elements, &(&1.position == element.position - 1))
        persist_element_deletion(socket, element, prev)
    end
  end

  def persist_element_deletion(socket, element, prev) do
    Sheets.delete_screenplay_element_references(element.id)

    case Screenplays.delete_element(element) do
      {:ok, _} ->
        reloaded = Screenplays.list_elements(socket.assigns.screenplay.id)

        socket = assign_elements(socket, reloaded)

        socket =
          if prev do
            Phoenix.LiveView.push_event(socket, "focus_element", %{id: prev.id})
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "Could not delete element."))}
    end
  end

  def do_update_screenplay_condition(socket, id, condition) do
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not save condition."))}
        end
    end
  end

  def do_update_screenplay_instruction(socket, id, assignments) do
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not save instruction."))}
        end
    end
  end

  def do_add_response_choice(socket, id) do
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not add choice."))}
        end
    end
  end

  def do_remove_response_choice(socket, id, choice_id) do
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not remove choice."))}
        end
    end
  end

  def do_update_response_choice_text(socket, id, choice_id, text) do
    update_choice_field(socket, id, choice_id, fn choice ->
      Map.put(choice, "text", text)
    end)
  end

  def do_toggle_choice_condition(socket, id, choice_id) do
    update_choice_field(socket, id, choice_id, fn choice ->
      if choice["condition"],
        do: Map.delete(choice, "condition"),
        else: Map.put(choice, "condition", Condition.new())
    end)
  end

  def do_toggle_choice_instruction(socket, id, choice_id) do
    update_choice_field(socket, id, choice_id, fn choice ->
      if choice["instruction"],
        do: Map.delete(choice, "instruction"),
        else: Map.put(choice, "instruction", [])
    end)
  end

  def do_set_character_sheet(socket, id, sheet_id) do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_character_sheet(socket, element, sheet_id)
    end
  end

  def persist_character_sheet(socket, element, sheet_id) do
    sheet_id = parse_int(sheet_id)
    sheet = sheet_id && Map.get(socket.assigns.sheets_map, sheet_id)
    name = if sheet, do: String.upcase(sheet.name), else: element.content
    data = Map.put(element.data || %{}, "sheet_id", sheet_id)

    case Screenplays.update_element(element, %{content: name, data: data}) do
      {:ok, updated} ->
        Sheets.update_screenplay_element_references(updated)
        {:noreply, update_element_in_list(socket, updated)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "Could not set character sheet."))}
    end
  end

  def do_update_dual_dialogue(socket, id, side, field, value)
      when side in @valid_dual_sides and field in @valid_dual_fields do
    case find_element(socket, id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_dual_dialogue_field(socket, element, side, field, value)
    end
  end

  def do_update_dual_dialogue(socket, _id, _side, _field, _value), do: {:noreply, socket}

  def persist_dual_dialogue_field(socket, element, side, field, value) do
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
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "Could not update dual dialogue."))}
    end
  end

  def do_toggle_dual_parenthetical(socket, id, side) when side in @valid_dual_sides do
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not toggle parenthetical."))}
        end
    end
  end

  def do_toggle_dual_parenthetical(socket, _id, _side), do: {:noreply, socket}

  def do_update_title_page(socket, id, field, value)
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
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not update title page."))}
        end
    end
  end

  def do_update_title_page(socket, _id, _field, _value), do: {:noreply, socket}

  def update_choice_field(socket, element_id, choice_id, update_fn) do
    case find_element(socket, element_id) do
      nil ->
        {:noreply, socket}

      element ->
        persist_choice_update(socket, element, choice_id, update_fn)
    end
  end

  def persist_choice_update(socket, element, choice_id, update_fn) do
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

  def handle_search_character_sheets(%{"query" => query}, socket) do
    results =
      Sheets.search_referenceable(socket.assigns.project.id, query, ["sheet"])
      |> Enum.map(fn item -> %{id: item.id, name: item.name, shortcut: item.shortcut} end)

    {:noreply, push_event(socket, "character_sheet_results", %{items: results})}
  end

  def handle_mention_suggestions(%{"query" => query}, socket) do
    results =
      Sheets.search_referenceable(socket.assigns.project.id, query, ["sheet"])
      |> Enum.map(fn item ->
        %{id: to_string(item.id), name: item.name, shortcut: item.shortcut, type: "sheet"}
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: results})}
  end

  def handle_navigate_to_sheet(%{"sheet_id" => sheet_id}, socket) do
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
end
