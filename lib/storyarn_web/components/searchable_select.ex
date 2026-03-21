defmodule StoryarnWeb.Components.SearchableSelect do
  @moduledoc """
  Unified searchable select LiveComponent — THE selector for the entire app.

  Supports static options (client-side filtering), server search (MFA + pagination),
  single or multi-select, custom option rendering, and create-new.

  ## Communication

  Selection events are pushed by the JS hook directly to the parent:

      # Default: pushEvent to LiveView
      LiveView.handle_event(on_select, %{"id" => "123"}, socket)

      # With target: pushEventTo to a LiveComponent
      LiveComponent.handle_event(on_select, %{"id" => "123"}, socket)

      # Multi-select create:
      handle_event(on_select, %{"value" => "new tag", "action" => "create"}, socket)

      # None/clear:
      handle_event(on_select, %{"id" => ""}, socket)

  ## Usage

      # Static options, single select
      <.live_component module={SearchableSelect} id="role"
        options={[%{id: "admin", name: "Admin"}, %{id: "member", name: "Member"}]}
        value="admin"
        on_select="update_role"
      />

      # Server search, single select
      <.live_component module={SearchableSelect} id="sheet-picker"
        search_fn={{EntitySearch, :search_entities, [:sheet, @project.id]}}
        get_name_fn={{EntitySearch, :get_entity_name, [:sheet, @project.id]}}
        value={@sheet_id}
        on_select="select_sheet"
      />

      # Static options, multi-select with create
      <.live_component module={SearchableSelect} id="tags"
        options={[%{id: "red", name: "Red"}, %{id: "blue", name: "Blue"}]}
        value={["red"]}
        multiple={true}
        allow_create={true}
        on_select="update_tags"
      />

      # Target a LiveComponent
      <.live_component module={SearchableSelect} id="audio"
        options={Enum.map(@audio_assets, &%{id: &1.id, name: &1.filename})}
        value={@selected_asset_id}
        on_select="select_audio"
        target={@myself}
      />

      # Custom option rendering
      <.live_component module={SearchableSelect} id="ref"
        search_fn={{EntitySearch, :search_entities_multi, [[:sheet, :flow], @project.id]}}
        get_name_fn={{EntitySearch, :get_entity_name_multi, [[:sheet, :flow], @project.id]}}
        value={@ref_id}
        on_select="select_reference">
        <:option :let={item}>
          <.icon name="file-text" class="size-3 opacity-60" />
          <span class="truncate">{item.name}</span>
        </:option>
      </.live_component>
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
       selected_names: %{},
       query: "",
       has_more: false,
       _source_key: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    source_key = assigns[:search_fn] || assigns[:options]
    prev_source_key = socket.assigns[:_source_key]
    prev_value = socket.assigns[:value]

    socket = assign(socket, assigns)

    # Fetch items when source changes (server search mode)
    socket =
      if assigns[:search_fn] && source_key != prev_source_key do
        items = do_search(assigns.search_fn, "", 0)
        has_more = length(items) >= @page_size

        socket
        |> assign(:_source_key, source_key)
        |> assign(:items, items)
        |> assign(:query, "")
        |> assign(:has_more, has_more)
      else
        assign(socket, :_source_key, source_key)
      end

    # Resolve display name(s) when value changes
    socket =
      if assigns[:value] != prev_value do
        if assigns[:multiple] do
          assign(socket, :selected_names, resolve_multi_names(socket.assigns))
        else
          assign(socket, :selected_name, resolve_display_name(socket.assigns))
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:options, fn -> nil end)
      |> assign_new(:search_fn, fn -> nil end)
      |> assign_new(:get_name_fn, fn -> nil end)
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:multiple, fn -> false end)
      |> assign_new(:allow_create, fn -> false end)
      |> assign_new(:allow_none, fn -> true end)
      |> assign_new(:on_select, fn -> "select" end)
      |> assign_new(:target, fn -> nil end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> gettext("Select...") end)
      |> assign_new(:search_placeholder, fn -> gettext("Search...") end)
      |> assign_new(:none_label, fn -> gettext("None") end)
      |> assign_new(:empty_label, fn -> gettext("No matches") end)
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:match_trigger_width, fn -> false end)

    ~H"""
    <div>
      <label :if={@label} class="block text-xs font-medium text-base-content/60 mb-1">
        {@label}
      </label>
      <div
        id={@id}
        phx-hook="PopoverSelect"
        data-phx-target={"##{@id}"}
        data-select-target={encode_target(@target)}
        data-select-event={@on_select}
        data-search-mode={search_mode(@options, @search_fn)}
        data-mode={if @multiple, do: "multi", else: "single"}
        data-selected={selected_string(@value)}
        data-active-class="bg-base-content/10 font-semibold text-primary"
        {if @match_trigger_width, do: [{"data-match-trigger-width", ""}], else: []}
      >
        <%!-- Trigger button --%>
        <%= if render_slot_present?(assigns, :trigger) do %>
          <button
            data-role="trigger"
            type="button"
            class="btn btn-ghost btn-sm w-full justify-start gap-1 border border-base-300 bg-base-100 font-normal"
            disabled={@disabled}
          >
            {render_slot(@trigger)}
          </button>
        <% else %>
          <button
            data-role="trigger"
            type="button"
            class="btn btn-ghost btn-sm w-full justify-between border border-base-300 bg-base-100 font-normal"
            disabled={@disabled}
          >
            <%= if @multiple do %>
              <span class="flex min-w-0 flex-wrap items-center gap-1">
                <%= if selected_values(@value) == [] do %>
                  <span class="text-sm opacity-50">{@placeholder}</span>
                <% else %>
                  <span
                    :for={val <- selected_values(@value)}
                    class="badge badge-sm badge-ghost"
                  >
                    {Map.get(@selected_names, to_string(val), to_string(val))}
                  </span>
                <% end %>
              </span>
            <% else %>
              <span class="min-w-0 truncate text-sm">
                {if @selected_name, do: @selected_name, else: @placeholder}
              </span>
            <% end %>
            <.icon name="chevron-down" class="size-3 shrink-0 opacity-50" />
          </button>
        <% end %>

        <%!-- Source div: LiveView patches this, hook clones into popover --%>
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
            <%!-- None option (single-select only) --%>
            <button
              :if={@allow_none && !@multiple}
              type="button"
              data-role="option"
              data-params={Jason.encode!(%{"id" => ""})}
              data-value=""
              data-search-text=""
              class="flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              {@none_label}
            </button>

            <%!-- Items --%>
            <button
              :for={item <- display_items(assigns)}
              type="button"
              data-role="option"
              data-params={Jason.encode!(%{"id" => to_string(item.id)})}
              data-value={to_string(item.id)}
              data-search-text={String.downcase(to_string(item.name))}
              class="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              <%= if render_slot_present?(assigns, :option) do %>
                {render_slot(@option, item)}
              <% else %>
                <span class="min-w-0 truncate">{item.name}</span>
              <% end %>
            </button>

            <%!-- Infinite scroll sentinel --%>
            <div
              :if={@has_more}
              data-role="sentinel"
              class="flex items-center justify-center py-2"
            >
              <span class="loading loading-spinner loading-xs text-base-content/30"></span>
            </div>
          </div>

          <%!-- Add-input for multi-select create --%>
          <div
            :if={@allow_create && @multiple}
            class="border-t border-base-content/10 p-2"
          >
            <input
              data-role="add-input"
              type="text"
              placeholder={gettext("Add new...")}
              class="input input-xs input-bordered w-full"
              autocomplete="off"
            />
          </div>

          <%!-- Empty state --%>
          <div
            data-role="empty"
            class="px-3 py-2 text-xs italic text-base-content/40"
            style={
              if display_items(assigns) != [] || (@allow_none && !@multiple),
                do: "display:none"
            }
          >
            {@empty_label}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Internal events (pushed by JS hook to this component)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
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

  defp display_items(%{options: options}) when is_list(options), do: options
  defp display_items(%{items: items}), do: items

  defp search_mode(options, _search_fn) when is_list(options), do: "client"
  defp search_mode(_options, search_fn) when is_tuple(search_fn), do: "server"
  defp search_mode(_, _), do: "client"

  defp encode_target(nil), do: nil
  defp encode_target(%{cid: cid}), do: to_string(cid)
  defp encode_target(target), do: to_string(target)

  defp selected_string(nil), do: ""
  defp selected_string(values) when is_list(values), do: Enum.map_join(values, ",", &to_string/1)
  defp selected_string(value), do: to_string(value)

  defp selected_values(nil), do: []
  defp selected_values(values) when is_list(values), do: values
  defp selected_values(_value), do: []

  defp render_slot_present?(assigns, slot_name) do
    case Map.get(assigns, slot_name) do
      [_ | _] -> true
      _ -> false
    end
  end

  # Single-select name resolution
  defp resolve_display_name(%{value: nil}), do: nil
  defp resolve_display_name(%{value: ""}), do: nil

  defp resolve_display_name(%{options: options, value: value}) when is_list(options) do
    str_val = to_string(value)
    case Enum.find(options, fn item -> to_string(item.id) == str_val end) do
      nil -> nil
      item -> item.name
    end
  end

  defp resolve_display_name(%{items: items, value: value} = assigns) do
    str_val = to_string(value)

    case Enum.find(items, fn item -> to_string(item.id) == str_val end) do
      nil ->
        if assigns[:get_name_fn] do
          parsed_id = parse_id(value)
          do_get_name(assigns.get_name_fn, parsed_id)
        end

      item ->
        item.name
    end
  end

  # Multi-select name resolution
  defp resolve_multi_names(%{value: nil}), do: %{}
  defp resolve_multi_names(%{value: values} = assigns) when is_list(values) do
    all_items = display_items(assigns)

    Map.new(values, fn val ->
      str_val = to_string(val)

      name =
        case Enum.find(all_items, fn item -> to_string(item.id) == str_val end) do
          nil -> str_val
          item -> item.name
        end

      {str_val, name}
    end)
  end

  defp resolve_multi_names(_), do: %{}

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp parse_id(value), do: value
end
