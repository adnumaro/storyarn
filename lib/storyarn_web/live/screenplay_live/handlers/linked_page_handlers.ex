defmodule StoryarnWeb.ScreenplayLive.Handlers.LinkedPageHandlers do
  @moduledoc """
  Linked page handlers for the screenplay LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Screenplays

  import StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers

  def do_create_linked_page(socket, element_id, choice_id) do
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

  def do_navigate_to_linked_page(socket, element_id, choice_id) do
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

  def do_unlink_choice_screenplay(socket, element_id, choice_id) do
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

  def do_generate_all_linked_pages(socket, element_id) do
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

  def create_pages_for_choices(_screenplay, element, []), do: {:ok, element}

  def create_pages_for_choices(screenplay, element, [choice | rest]) do
    case Screenplays.create_linked_page(screenplay, element, choice["id"]) do
      {:ok, _child, updated_element} ->
        create_pages_for_choices(screenplay, updated_element, rest)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load_linked_pages(screenplay) do
    Screenplays.list_child_screenplays(screenplay.id)
    |> Map.new(fn s -> {s.id, s.name} end)
  end

  def valid_navigation_target?(socket, screenplay_id) do
    Screenplays.screenplay_exists?(socket.assigns.project.id, screenplay_id)
  end
end
