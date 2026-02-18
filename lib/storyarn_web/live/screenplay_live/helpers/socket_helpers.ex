defmodule StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers do
  @moduledoc """
  Socket and utility helpers for the screenplay LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.ContentUtils
  alias Storyarn.Screenplays.TiptapSerialization

  def parse_int(""), do: nil
  def parse_int(nil), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def screenplays_path(socket, screenplay_id \\ nil)

  def screenplays_path(socket, nil) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays"
  end

  def screenplays_path(socket, screenplay_id) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{screenplay_id}"
  end

  def reload_screenplays_tree(socket) do
    assign(
      socket,
      :screenplays_tree,
      Screenplays.list_screenplays_tree(socket.assigns.project.id)
    )
  end

  def find_element(socket, id) do
    id =
      cond do
        is_integer(id) -> id
        is_binary(id) -> parse_int(id)
        true -> nil
      end

    if id, do: Enum.find(socket.assigns.elements, &(&1.id == id)), else: nil
  end

  def update_element_in_list(socket, updated_element) do
    elements =
      Enum.map(socket.assigns.elements, fn el ->
        if el.id == updated_element.id, do: updated_element, else: el
      end)

    assign_elements(socket, elements)
  end

  # Mount/reconnect: computes editor_doc for initial render
  def assign_elements_with_editor_doc(socket, elements) do
    socket
    |> assign(:elements, elements)
    |> assign(:editor_doc, TiptapSerialization.elements_to_doc(elements))
  end

  # Post-mount updates: skips editor_doc recomputation (client owns the doc)
  def assign_elements(socket, elements) do
    assign(socket, :elements, elements)
  end

  # Push full editor content to TipTap after server-side bulk updates (e.g. flow sync).
  # The LiveViewBridge extension listens for "set_editor_content" and replaces the doc.
  def push_editor_content(socket, elements) do
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
  def push_element_data_updated(socket, %{id: id, data: data}) do
    push_event(socket, "element_data_updated", %{element_id: id, data: data || %{}})
  end

  # ---------------------------------------------------------------------------
  # Shared validation constants (used as module attributes in handlers)
  # ---------------------------------------------------------------------------

  def valid_dual_sides, do: ~w(left right)
  def valid_dual_fields, do: ~w(character parenthetical dialogue)
  def valid_title_fields, do: ~w(title credit author draft_date contact)

  # ---------------------------------------------------------------------------
  # Shared sanitization helper
  # ---------------------------------------------------------------------------

  def sanitize_plain_text(value) when is_binary(value), do: ContentUtils.strip_html(value)
  def sanitize_plain_text(_), do: ""
end
