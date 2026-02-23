defmodule StoryarnWeb.FlowLive.Components.FlowToolbar do
  @moduledoc """
  Floating toolbar component for flow nodes.

  Renders a compact, per-type toolbar above the selected node.
  Dispatches to private type-specific toolbar functions.
  """
  use StoryarnWeb, :html
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [node_type_icon: 1]

  @color_swatches [
    ~w(#ef4444 #f97316 #f59e0b #eab308 #22c55e #14b8a6 #3b82f6 #6366f1 #8b5cf6 #a855f7 #ec4899 #000000),
    ~w(#fca5a5 #fdba74 #fde68a #a7f3d0 #a5f3fc #93c5fd #c4b5fd #e9d5ff #fbcfe8 #e5e7eb #ffffff)
  ]

  attr :node, :map, required: true
  attr :form, :any, required: true
  attr :can_edit, :boolean, required: true
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :available_flows, :list, default: []
  attr :flow_search_has_more, :boolean, default: false
  attr :flow_search_deep, :boolean, default: false
  attr :subflow_exits, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :referencing_flows, :list, default: []
  attr :project_maps, :list, default: []
  attr :available_maps, :list, default: []

  def node_toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 text-sm">
      {render_toolbar(@node.type, assigns)}
    </div>
    """
  end

  # ── Entry ──────────────────────────────────────────────────────────────

  defp render_toolbar("entry", assigns) do
    ref_count = length(assigns.referencing_flows)
    assigns = assign(assigns, :ref_count, ref_count)

    ~H"""
    <.node_type_icon type="entry" />
    <span class="text-xs font-medium opacity-70">{dgettext("flows", "Entry point")}</span>
    <span :if={@ref_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} ref", "%{count} refs", @ref_count, count: @ref_count)}
    </span>
    """
  end

  # ── Dialogue ───────────────────────────────────────────────────────────

  defp render_toolbar("dialogue", assigns) do
    speaker_id = assigns.form[:speaker_sheet_id].value
    response_count = length(assigns.node.data["responses"] || [])
    has_audio = assigns.node.data["audio_asset_id"] not in [nil, ""]

    selected_speaker =
      Enum.find_value(assigns.all_sheets, fn s ->
        if to_string(s.id) == to_string(speaker_id), do: s.name
      end)

    assigns =
      assigns
      |> assign(:response_count, response_count)
      |> assign(:has_audio, has_audio)
      |> assign(:selected_speaker, selected_speaker)
      |> assign(:speaker_id, speaker_id)

    ~H"""
    <.toolbar_searchable_select
      :if={@can_edit}
      id={"dialogue-speaker-#{@node.id}"}
      options={Enum.map(@all_sheets, &{&1.name, &1.id})}
      selected_value={@speaker_id}
      selected_label={@selected_speaker}
      placeholder={dgettext("flows", "Speaker…")}
      event="update_node_data"
      event_params_fn={fn value -> %{node: %{speaker_sheet_id: value}} end}
    />
    <span :if={!@can_edit && @selected_speaker} class="text-xs truncate max-w-[100px]">
      {@selected_speaker}
    </span>
    <.icon :if={@has_audio} name="volume-2" class="size-3.5 text-info" />
    <span :if={@response_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} response", "%{count} responses", @response_count,
        count: @response_count
      )}
    </span>
    <span class="toolbar-separator"></span>
    <button type="button" phx-click="open_screenplay" class="toolbar-btn text-xs font-medium">
      {dgettext("flows", "Edit")}
    </button>
    <button
      type="button"
      phx-click="start_preview"
      phx-value-id={@node.id}
      class="toolbar-btn text-xs"
    >
      <.icon name="play" class="size-3" />
    </button>
    """
  end

  # ── Condition ──────────────────────────────────────────────────────────

  defp render_toolbar("condition", assigns) do
    condition = assigns.node.data["condition"]
    rules = if is_map(condition), do: condition["rules"] || [], else: []
    rule_count = length(rules)
    switch_mode = assigns.node.data["switch_mode"] == true

    assigns =
      assigns
      |> assign(:rule_count, rule_count)
      |> assign(:switch_mode, switch_mode)

    ~H"""
    <.node_type_icon type="condition" />
    <span class="text-xs font-medium opacity-70">{dgettext("flows", "Condition")}</span>
    <button
      :if={@can_edit}
      type="button"
      phx-click="toggle_switch_mode"
      class={"toolbar-btn text-xs #{if @switch_mode, do: "toolbar-btn-active"}"}
      title={dgettext("flows", "Toggle switch mode")}
    >
      <.icon name="split" class="size-3.5" />
    </button>
    <span :if={@rule_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} rule", "%{count} rules", @rule_count, count: @rule_count)}
    </span>
    <span class="toolbar-separator"></span>
    <button type="button" phx-click="open_builder" class="toolbar-btn text-xs font-medium">
      {dgettext("flows", "Edit")}
    </button>
    """
  end

  # ── Instruction ────────────────────────────────────────────────────────

  defp render_toolbar("instruction", assigns) do
    assignments = assigns.node.data["assignments"] || []
    assignment_count = length(assignments)
    description = assigns.node.data["description"] || ""

    assigns =
      assigns
      |> assign(:assignment_count, assignment_count)
      |> assign(:description, description)

    ~H"""
    <.node_type_icon type="instruction" />
    <span :if={@description != ""} class="text-xs opacity-70 max-w-[120px] truncate">
      {@description}
    </span>
    <span :if={@description == ""} class="text-xs font-medium opacity-70">
      {dgettext("flows", "Instruction")}
    </span>
    <span :if={@assignment_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} assignment", "%{count} assignments", @assignment_count,
        count: @assignment_count
      )}
    </span>
    <span class="toolbar-separator"></span>
    <button type="button" phx-click="open_builder" class="toolbar-btn text-xs font-medium">
      {dgettext("flows", "Edit")}
    </button>
    """
  end

  # ── Hub ────────────────────────────────────────────────────────────────

  defp render_toolbar("hub", assigns) do
    jump_count = length(assigns.referencing_jumps)
    color = assigns.node.data["color"] || "#3b82f6"

    assigns =
      assigns
      |> assign(:jump_count, jump_count)
      |> assign(:color, color)
      |> assign(:color_swatches, @color_swatches)

    ~H"""
    <.form
      :if={@can_edit}
      for={@form}
      phx-change="update_node_data"
      phx-debounce="500"
      class="contents"
    >
      <input
        type="text"
        name="node[label]"
        value={@form[:label].value}
        placeholder={dgettext("flows", "Label…")}
        class="toolbar-input w-[100px]"
      />
      <input
        type="text"
        name="node[hub_id]"
        value={@form[:hub_id].value}
        placeholder="hub_id"
        class="toolbar-input w-[80px] font-mono text-xs"
      />
    </.form>
    <%!-- Color swatch — popover picker --%>
    <div
      phx-hook="ToolbarPopover"
      id={"popover-hub-color-#{@node.id}"}
      data-width="160px"
      data-placement="bottom"
      data-offset="6"
    >
      <button
        data-role="trigger"
        type="button"
        class="toolbar-btn"
        title={dgettext("flows", "Hub color")}
        disabled={!@can_edit}
      >
        <span
          class="inline-block size-4 rounded-full border border-white/20 shrink-0"
          style={"background:#{@color}"}
        />
      </button>
      <template data-role="popover-template">
        <div class="p-2">
          <div class="text-xs font-medium text-base-content/60 mb-1.5">
            {dgettext("flows", "Hub color")}
          </div>
          <div :for={row <- @color_swatches} class="flex gap-1 mb-1">
            <button
              :for={swatch <- row}
              type="button"
              data-event="update_hub_color"
              data-params={Jason.encode!(%{color: swatch})}
              class={"color-swatch #{if swatch == @color, do: "color-swatch-active"}"}
              style={"background:#{swatch}"}
              title={swatch}
              disabled={!@can_edit}
            />
          </div>
        </div>
      </template>
    </div>
    <span :if={@jump_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} jump", "%{count} jumps", @jump_count, count: @jump_count)}
    </span>
    """
  end

  # ── Jump ───────────────────────────────────────────────────────────────

  defp render_toolbar("jump", assigns) do
    target = assigns.form[:target_hub_id].value || ""

    selected_hub_label =
      Enum.find_value(assigns.flow_hubs, fn h ->
        if h.hub_id == target, do: h.hub_id
      end)

    assigns =
      assigns
      |> assign(:target, target)
      |> assign(:selected_hub_label, selected_hub_label)

    ~H"""
    <.node_type_icon type="jump" />
    <.toolbar_searchable_select
      :if={@can_edit}
      id={"jump-hub-#{@node.id}"}
      options={Enum.map(@flow_hubs, &{&1.hub_id, &1.hub_id})}
      selected_value={@target}
      selected_label={@selected_hub_label}
      placeholder={dgettext("flows", "Target hub…")}
      event="update_node_data"
      event_params_fn={fn value -> %{node: %{target_hub_id: value}} end}
    />
    <span :if={!@can_edit && @selected_hub_label} class="text-xs font-mono">
      {@selected_hub_label}
    </span>
    <button
      :if={@target != ""}
      type="button"
      phx-click="navigate_to_hub"
      phx-value-id={@node.id}
      class="toolbar-btn text-xs"
      title={dgettext("flows", "Locate target hub")}
    >
      <.icon name="crosshair" class="size-3.5" />
    </button>
    """
  end

  # ── Exit ───────────────────────────────────────────────────────────────

  defp render_toolbar("exit", assigns) do
    exit_mode = assigns.node.data["exit_mode"] || "terminal"
    color = assigns.node.data["outcome_color"] || "#22c55e"
    has_ref = assigns.node.data["referenced_flow_id"] not in [nil, ""]
    target_type = assigns.node.data["target_type"]
    target_id = assigns.node.data["target_id"]

    exit_target_label = resolve_exit_target_label(target_type, target_id, assigns)

    assigns =
      assigns
      |> assign(:exit_mode, exit_mode)
      |> assign(:color, color)
      |> assign(:has_ref, has_ref)
      |> assign(:target_type, target_type)
      |> assign(:target_id, target_id)
      |> assign(:exit_target_label, exit_target_label)
      |> assign(:color_swatches, @color_swatches)

    ~H"""
    <.form
      :if={@can_edit}
      for={@form}
      phx-change="update_node_data"
      phx-debounce="500"
      class="contents"
    >
      <input
        type="text"
        name="node[label]"
        value={@form[:label].value}
        placeholder={dgettext("flows", "Label…")}
        class="toolbar-input w-[100px]"
      />
    </.form>
    <%!-- Exit Mode — popover with icon + label + description --%>
    <div
      phx-hook="ToolbarPopover"
      id={"popover-exit-mode-#{@node.id}"}
      data-width="14rem"
      data-offset="6"
    >
      <button
        data-role="trigger"
        type="button"
        class="toolbar-btn gap-1 px-1.5"
        disabled={!@can_edit}
      >
        <.exit_mode_icon mode={@exit_mode} />
        <span class="text-xs">{exit_mode_label(@exit_mode)}</span>
        <.icon name="chevron-down" class="size-3 opacity-50" />
      </button>
      <template data-role="popover-template">
        <div class="p-1">
          <button
            :for={mode <- ~w(terminal flow_reference caller_return)}
            type="button"
            data-event="update_exit_mode"
            data-params={Jason.encode!(%{mode: mode})}
            class={"flex items-center gap-2.5 w-full px-2.5 py-2 rounded-md text-left hover:bg-base-200 #{if @exit_mode == mode, do: "bg-base-200 font-medium"}"}
            disabled={!@can_edit}
          >
            <.exit_mode_icon mode={mode} size="size-5" />
            <div>
              <div class="text-sm leading-tight">{exit_mode_label(mode)}</div>
              <div class="text-xs text-base-content/50 leading-tight">
                {exit_mode_description(mode)}
              </div>
            </div>
          </button>
        </div>
      </template>
    </div>
    <%!-- Color swatch — popover picker --%>
    <div
      phx-hook="ToolbarPopover"
      id={"popover-exit-color-#{@node.id}"}
      data-width="160px"
      data-placement="bottom"
      data-offset="6"
    >
      <button
        data-role="trigger"
        type="button"
        class="toolbar-btn"
        title={dgettext("flows", "Outcome color")}
        disabled={!@can_edit}
      >
        <span
          class="inline-block size-4 rounded-full border border-white/20 shrink-0"
          style={"background:#{@color}"}
        />
      </button>
      <template data-role="popover-template">
        <div class="p-2">
          <div class="text-xs font-medium text-base-content/60 mb-1.5">
            {dgettext("flows", "Outcome color")}
          </div>
          <div :for={row <- @color_swatches} class="flex gap-1 mb-1">
            <button
              :for={swatch <- row}
              type="button"
              data-event="update_outcome_color"
              data-params={Jason.encode!(%{color: swatch})}
              class={"color-swatch #{if swatch == @color, do: "color-swatch-active"}"}
              style={"background:#{swatch}"}
              title={swatch}
              disabled={!@can_edit}
            />
          </div>
        </div>
      </template>
    </div>
    <%!-- Target picker (terminal mode only) --%>
    <.exit_target_picker
      :if={@exit_mode == "terminal" && @can_edit}
      node={@node}
      target_type={@target_type}
      target_id={@target_id}
      exit_target_label={@exit_target_label}
      available_maps={@available_maps}
      available_flows={@available_flows}
    />
    <button
      :if={@has_ref}
      type="button"
      phx-click="navigate_to_exit_flow"
      phx-value-flow-id={@node.data["referenced_flow_id"]}
      class="toolbar-btn text-xs"
      title={dgettext("flows", "Open referenced flow")}
    >
      <.icon name="external-link" class="size-3.5" />
    </button>
    """
  end

  # ── Subflow ────────────────────────────────────────────────────────────

  defp render_toolbar("subflow", assigns) do
    ref_id = assigns.node.data["referenced_flow_id"]
    has_ref = ref_id not in [nil, ""]
    exit_count = length(assigns.subflow_exits)

    selected_flow_name =
      Enum.find_value(assigns.available_flows, fn f ->
        if to_string(f.id) == to_string(ref_id), do: f.name
      end)

    assigns =
      assigns
      |> assign(:has_ref, has_ref)
      |> assign(:ref_id, ref_id)
      |> assign(:exit_count, exit_count)
      |> assign(:selected_flow_name, selected_flow_name)

    ~H"""
    <.node_type_icon type="subflow" />
    <.toolbar_searchable_select
      :if={@can_edit}
      id={"subflow-flow-#{@node.id}"}
      options={Enum.map(@available_flows, &{&1.name, &1.id})}
      selected_value={@ref_id}
      selected_label={@selected_flow_name}
      placeholder={dgettext("flows", "Select flow…")}
      event="update_subflow_reference"
      event_params_fn={fn value -> %{referenced_flow_id: value} end}
      server_search_event="search_available_flows"
      has_more={@flow_search_has_more}
      load_more_event="search_flows_more"
      deep_search={@flow_search_deep}
      deep_search_event="toggle_deep_search"
    />
    <span :if={!@can_edit && @selected_flow_name} class="text-xs truncate max-w-[120px]">
      {@selected_flow_name}
    </span>
    <button
      :if={@has_ref}
      type="button"
      phx-click="navigate_to_subflow"
      phx-value-flow-id={@ref_id}
      class="toolbar-btn text-xs"
      title={dgettext("flows", "Open referenced flow")}
    >
      <.icon name="external-link" class="size-3.5" />
    </button>
    <span :if={@exit_count > 0} class="badge badge-xs badge-ghost">
      {dngettext("flows", "%{count} exit", "%{count} exits", @exit_count, count: @exit_count)}
    </span>
    """
  end

  # ── Scene ──────────────────────────────────────────────────────────────

  defp render_toolbar("scene", assigns) do
    location_id = assigns.form[:location_sheet_id].value
    int_ext = assigns.node.data["int_ext"] || ""
    time = assigns.node.data["time_of_day"] || ""

    selected_location =
      Enum.find_value(assigns.all_sheets, fn s ->
        if to_string(s.id) == to_string(location_id), do: s.name
      end)

    assigns =
      assigns
      |> assign(:location_id, location_id)
      |> assign(:selected_location, selected_location)
      |> assign(:int_ext, int_ext)
      |> assign(:time, time)

    ~H"""
    <.node_type_icon type="scene" />
    <.toolbar_searchable_select
      :if={@can_edit}
      id={"scene-location-#{@node.id}"}
      options={Enum.map(@all_sheets, &{&1.name, &1.id})}
      selected_value={@location_id}
      selected_label={@selected_location}
      placeholder={dgettext("flows", "Location…")}
      event="update_node_data"
      event_params_fn={fn value -> %{node: %{location_sheet_id: value}} end}
    />
    <span :if={!@can_edit && @selected_location} class="text-xs truncate max-w-[100px]">
      {@selected_location}
    </span>
    <div :if={@can_edit} class="flex items-center gap-0.5">
      <button
        :for={mode <- ~w(int ext int_ext)}
        type="button"
        phx-click={JS.push("update_node_data", value: %{node: %{int_ext: mode}})}
        class={"toolbar-btn text-xs #{if @int_ext == mode, do: "toolbar-btn-active"}"}
      >
        {String.upcase(mode)}
      </button>
    </div>
    <.toolbar_searchable_select
      :if={@can_edit}
      id={"scene-time-#{@node.id}"}
      options={Enum.map(~w(day night morning evening continuous), &{String.capitalize(&1), &1})}
      selected_value={@time}
      selected_label={if @time != "", do: String.capitalize(@time)}
      placeholder={dgettext("flows", "Time…")}
      event="update_node_data"
      event_params_fn={fn value -> %{node: %{time_of_day: value}} end}
    />
    """
  end

  # ── Fallback ───────────────────────────────────────────────────────────

  defp render_toolbar(_type, assigns) do
    ~H"""
    <span class="text-xs opacity-50">{dgettext("flows", "No toolbar for this type")}</span>
    """
  end

  # ════════════════════════════════════════════════════════════════════════
  # Shared: Searchable Select
  # ════════════════════════════════════════════════════════════════════════

  defp toolbar_searchable_select(assigns) do
    # Pre-compute the phx-click values for each option
    options_with_params =
      Enum.map(assigns.options, fn {label, value} ->
        params = assigns.event_params_fn.(value)
        {label, value, params}
      end)

    clear_params = assigns.event_params_fn.("")

    assigns =
      assigns
      |> assign(:options_with_params, options_with_params)
      |> assign(:clear_params, clear_params)
      |> assign_new(:server_search_event, fn -> nil end)
      |> assign_new(:has_more, fn -> false end)
      |> assign_new(:load_more_event, fn -> nil end)
      |> assign_new(:deep_search, fn -> false end)
      |> assign_new(:deep_search_event, fn -> nil end)

    ~H"""
    <div
      id={@id}
      phx-hook="SearchableSelect"
      {if @server_search_event, do: [{"data-server-search", @server_search_event}], else: []}
    >
      <button
        data-role="trigger"
        type="button"
        class="toolbar-btn gap-1 px-1.5 max-w-[160px]"
      >
        <span :if={@selected_label} class="text-xs truncate">{@selected_label}</span>
        <span :if={!@selected_label} class="text-xs opacity-50">{@placeholder}</span>
        <.icon name="chevron-down" class="size-3 opacity-50 shrink-0" />
      </button>
      <template data-role="popover-template">
        <div class="p-2 pb-1">
          <input
            data-role="search"
            type="text"
            placeholder={dgettext("flows", "Search…")}
            class="input input-xs input-bordered w-full"
            autocomplete="off"
          />
          <label
            :if={@deep_search_event}
            class="flex items-center gap-1.5 mt-1 cursor-pointer select-none"
          >
            <input
              type="checkbox"
              data-role="deep-search-toggle"
              class="toggle toggle-xs toggle-primary"
              checked={@deep_search}
              data-event={@deep_search_event}
            />
            <span class="text-[11px] text-base-content/50">
              {dgettext("flows", "Search in content")}
            </span>
          </label>
        </div>
        <div data-role="list" class="max-h-48 overflow-y-auto p-1">
          <button
            :if={@selected_value}
            type="button"
            data-event={@event}
            data-params={Jason.encode!(@clear_params)}
            data-search-text=""
            class="flex items-center gap-2 w-full px-2 py-1.5 rounded text-xs text-base-content/50 hover:bg-base-200"
          >
            <.icon name="x" class="size-3" />
            {dgettext("flows", "Clear")}
          </button>
          <button
            :for={{label, value, params} <- @options_with_params}
            type="button"
            data-event={@event}
            data-params={Jason.encode!(params)}
            data-search-text={String.downcase(label)}
            class={"flex items-center w-full px-2 py-1.5 rounded text-xs hover:bg-base-200 truncate #{if to_string(value) == to_string(@selected_value), do: "font-semibold text-primary"}"}
          >
            {label}
          </button>
          <button
            :if={@has_more && @load_more_event}
            type="button"
            data-role="load-more"
            data-event={@load_more_event}
            class="flex items-center justify-center w-full px-2 py-1.5 rounded text-xs text-primary hover:bg-base-200"
          >
            {dgettext("flows", "Show more…")}
          </button>
        </div>
        <div
          data-role="empty"
          class="px-3 py-2 text-xs text-base-content/40 italic"
          style="display:none"
        >
          {dgettext("flows", "No matches")}
        </div>
      </template>
    </div>
    """
  end

  # ════════════════════════════════════════════════════════════════════════
  # Helpers
  # ════════════════════════════════════════════════════════════════════════

  defp exit_mode_icon(assigns) do
    assigns = assign_new(assigns, :size, fn -> "size-3.5" end)

    ~H"""
    <.icon :if={@mode == "terminal"} name="square" class={@size} />
    <.icon :if={@mode == "flow_reference"} name="arrow-right" class={@size} />
    <.icon :if={@mode == "caller_return"} name="undo-2" class={@size} />
    """
  end

  defp exit_mode_label("terminal"), do: dgettext("flows", "Terminal")
  defp exit_mode_label("flow_reference"), do: dgettext("flows", "Continue to flow")
  defp exit_mode_label("caller_return"), do: dgettext("flows", "Return to caller")

  defp exit_mode_description("terminal"), do: dgettext("flows", "Ends the flow entirely")

  defp exit_mode_description("flow_reference"),
    do: dgettext("flows", "Continues into another flow")

  defp exit_mode_description("caller_return"),
    do: dgettext("flows", "Returns to the calling subflow")

  # ── Exit target picker ──────────────────────────────────────────────────

  defp exit_target_picker(assigns) do
    target_options = build_exit_target_options(assigns.available_maps, assigns.available_flows)

    selected_value =
      if assigns.target_type && assigns.target_id do
        "#{assigns.target_type}:#{assigns.target_id}"
      end

    assigns =
      assigns
      |> assign(:target_options, target_options)
      |> assign(:selected_value, selected_value)

    ~H"""
    <span class="toolbar-separator"></span>
    <.toolbar_searchable_select
      id={"exit-target-#{@node.id}"}
      options={@target_options}
      selected_value={@selected_value}
      selected_label={@exit_target_label}
      placeholder={dgettext("flows", "Transition…")}
      event="update_exit_target"
      event_params_fn={&parse_exit_target_value/1}
    />
    """
  end

  defp build_exit_target_options(maps, flows) do
    map_opts = Enum.map(maps, fn m -> {"#{m.name}", "map:#{m.id}"} end)
    flow_opts = Enum.map(flows, fn f -> {"#{f.name}", "flow:#{f.id}"} end)
    map_opts ++ flow_opts
  end

  defp parse_exit_target_value("") do
    %{"target_type" => "", "target_id" => ""}
  end

  defp parse_exit_target_value(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [type, id] -> %{"target_type" => type, "target_id" => id}
      _ -> %{"target_type" => "", "target_id" => ""}
    end
  end

  defp parse_exit_target_value(_), do: %{"target_type" => "", "target_id" => ""}

  defp resolve_exit_target_label(nil, _, _), do: nil
  defp resolve_exit_target_label(_, nil, _), do: nil

  defp resolve_exit_target_label("map", target_id, assigns) do
    Enum.find_value(assigns.available_maps, fn m ->
      if to_string(m.id) == to_string(target_id), do: m.name
    end)
  end

  defp resolve_exit_target_label("flow", target_id, assigns) do
    Enum.find_value(assigns.available_flows, fn f ->
      if to_string(f.id) == to_string(target_id), do: f.name
    end)
  end

  defp resolve_exit_target_label(_, _, _), do: nil
end
