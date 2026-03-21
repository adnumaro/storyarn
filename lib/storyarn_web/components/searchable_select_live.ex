defmodule StoryarnWeb.Components.SearchableSelectLive do
  @moduledoc """
  Generic searchable select LiveComponent with server-side search and infinite scroll.

  Driven by MFA tuples for maximum flexibility — works with any data source.

  ## Communication

      send(self(), {on_select, notify_id || component_id, selected_id_or_nil})

  ## Usage

      <.live_component
        module={SearchableSelectLive}
        id="audio-select-123"
        search_fn={{MyModule, :search_audio, [project_id]}}
        get_name_fn={{MyModule, :get_audio_name, [project_id]}}
        selected_id={@audio_id}
        label="Audio"
        on_select={:audio_selected}
      />

  ## MFA calling convention

  - `search_fn`: `apply(mod, fun, extra_args ++ [query, [limit: N, offset: N]])`
  - `get_name_fn`: `apply(mod, fun, extra_args ++ [id])`
  """

  use StoryarnWeb, :live_component
  use Gettext, backend: Storyarn.Gettext

  @page_size 20

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       items: [],
       selected_name: nil,
       query: "",
       has_more: false,
       _source_key: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    source_key = assigns[:search_fn]
    prev_source_key = socket.assigns[:_source_key]
    prev_selected = socket.assigns[:selected_id]

    socket = assign(socket, assigns)

    socket =
      if source_key != prev_source_key do
        items = do_search(assigns.search_fn, "", 0)
        has_more = length(items) >= @page_size

        socket
        |> assign(:_source_key, source_key)
        |> assign(:items, items)
        |> assign(:query, "")
        |> assign(:has_more, has_more)
      else
        socket
      end

    socket =
      if assigns[:selected_id] != prev_selected do
        name = resolve_selected_name(socket.assigns)
        assign(socket, :selected_name, name)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:allow_none, fn -> true end)
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> gettext("Select...") end)
      |> assign_new(:search_placeholder, fn -> gettext("Search...") end)
      |> assign_new(:none_label, fn -> gettext("None") end)
      |> assign_new(:empty_label, fn -> gettext("No matches") end)
      |> assign_new(:on_select, fn -> :searchable_selected end)
      |> assign_new(:notify_id, fn -> nil end)

    ~H"""
    <div>
      <label :if={@label} class="block text-xs font-medium text-base-content/60 mb-1">
        {@label}
      </label>
      <div
        id={@id}
        phx-hook="EntitySelect"
        data-phx-target={"##{@id}"}
        data-selected={if @selected_id, do: to_string(@selected_id), else: ""}
        data-active-class="bg-base-content/10 font-semibold text-primary"
        data-version={length(@items)}
      >
        <button
          data-role="trigger"
          type="button"
          class="btn btn-ghost btn-sm w-full justify-between border border-base-300 bg-base-100 font-normal"
          disabled={@disabled}
        >
          <span class="min-w-0 truncate text-sm">
            {if @selected_name, do: @selected_name, else: @placeholder}
          </span>
          <.icon name="chevron-down" class="size-3 shrink-0 opacity-50" />
        </button>

        <%!-- Source div: LiveView patches this. Hook reads it on updated(). --%>
        <div data-role="popover-source" style="display:none">
          <div class="p-2 pb-1">
            <input
              data-role="search"
              type="text"
              placeholder={@search_placeholder}
              class="input input-xs input-bordered w-full"
              autocomplete="off"
            />
          </div>
          <div data-role="list" class="max-h-56 overflow-y-auto p-1">
            <button
              :if={@allow_none}
              type="button"
              data-event="select_entity"
              data-params={Jason.encode!(%{"id" => ""})}
              data-value=""
              data-search-text=""
              class="flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              {@none_label}
            </button>
            <button
              :for={item <- @items}
              type="button"
              data-event="select_entity"
              data-params={Jason.encode!(%{"id" => to_string(item.id)})}
              data-value={to_string(item.id)}
              data-search-text={String.downcase(item.name)}
              class="flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              {item.name}
            </button>
            <div
              :if={@has_more}
              data-role="sentinel"
              class="flex items-center justify-center py-2"
            >
              <span class="loading loading-spinner loading-xs text-base-content/30"></span>
            </div>
          </div>
          <div
            data-role="empty"
            class="px-3 py-2 text-xs italic text-base-content/40"
            style={if @items != [] or @allow_none, do: "display:none"}
          >
            {@empty_label}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_entity", %{"id" => id}, socket) do
    parsed_id = if id == "", do: nil, else: String.to_integer(id)
    on_select = socket.assigns.on_select
    notify_id = socket.assigns[:notify_id] || socket.assigns.id

    send(self(), {on_select, notify_id, parsed_id})

    name =
      if parsed_id do
        find_in_list(socket.assigns.items, parsed_id) ||
          do_get_name(socket.assigns.get_name_fn, parsed_id)
      end

    {:noreply, assign(socket, selected_id: parsed_id, selected_name: name)}
  end

  def handle_event("search_entities", %{"query" => query}, socket) do
    items = do_search(socket.assigns.search_fn, query, 0)
    has_more = length(items) >= @page_size

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:query, query)
     |> assign(:has_more, has_more)}
  end

  def handle_event("load_more", _params, socket) do
    offset = length(socket.assigns.items)

    more = do_search(socket.assigns.search_fn, socket.assigns.query, offset)
    has_more = length(more) >= @page_size

    {:noreply,
     socket
     |> assign(:items, socket.assigns.items ++ more)
     |> assign(:has_more, has_more)}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_search({mod, fun, extra_args}, query, offset) do
    apply(mod, fun, extra_args ++ [query, [limit: @page_size, offset: offset]])
  end

  defp do_get_name({mod, fun, extra_args}, id) do
    apply(mod, fun, extra_args ++ [id])
  end

  defp find_in_list(items, id) do
    case Enum.find(items, &(&1.id == id)) do
      nil -> nil
      item -> item.name
    end
  end

  defp resolve_selected_name(%{selected_id: nil}), do: nil

  defp resolve_selected_name(%{items: items, selected_id: id} = assigns) do
    find_in_list(items, id) || do_get_name(assigns.get_name_fn, id)
  end
end
