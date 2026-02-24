defmodule StoryarnWeb.SheetLive.Components.VariableUsageSection do
  @moduledoc """
  LiveComponent that shows which flow nodes read/write each variable on a sheet.
  Lazy-loads usage data on first render.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Flows

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <section :if={@variable_blocks != []}>
        <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
          <.icon name="database" class="size-5" />
          {dgettext("sheets", "Variable Usage")}
          <span :if={@total_refs > 0} class="badge badge-sm">{@total_refs}</span>
        </h2>

        <%= if is_nil(@usage_map) do %>
          <div class="flex items-center justify-center p-8">
            <span class="loading loading-spinner loading-md"></span>
          </div>
        <% else %>
          <%= if @total_refs == 0 do %>
            <div class="bg-base-200/50 rounded-lg p-6 text-center">
              <p class="text-base-content/70 text-sm">
                {dgettext("sheets", "No variables on this sheet are used in any flow or scene yet.")}
              </p>
            </div>
          <% else %>
            <div class="space-y-4">
              <.variable_block_usage
                :for={block <- @variable_blocks}
                block={block}
                sheet={@sheet}
                usage={@usage_map[block.id]}
                workspace_slug={@workspace_slug}
                project_slug={@project_slug}
              />
            </div>
          <% end %>
        <% end %>
      </section>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:usage_map, fn -> nil end)
      |> assign_new(:total_refs, fn -> 0 end)

    # Compute variable blocks from all blocks
    variable_blocks =
      (assigns[:blocks] || [])
      |> Enum.filter(&variable_block?/1)

    socket = assign(socket, :variable_blocks, variable_blocks)

    # Extract workspace/project slugs for link building
    socket =
      socket
      |> assign(:workspace_slug, assigns.project.workspace.slug)
      |> assign(:project_slug, assigns.project.slug)

    socket =
      if is_nil(socket.assigns.usage_map) do
        load_usage(socket)
      else
        socket
      end

    {:ok, socket}
  end

  defp load_usage(socket) do
    variable_blocks = socket.assigns.variable_blocks
    project_id = socket.assigns.project.id

    usage_map =
      Map.new(variable_blocks, fn block ->
        usage = Flows.check_stale_references(block.id, project_id)
        reads = Enum.filter(usage, &(&1.kind == "read"))
        writes = Enum.filter(usage, &(&1.kind == "write"))
        {block.id, %{reads: reads, writes: writes}}
      end)

    total_refs =
      Enum.reduce(usage_map, 0, fn {_id, %{reads: reads, writes: writes}}, acc ->
        acc + length(reads) + length(writes)
      end)

    socket
    |> assign(:usage_map, usage_map)
    |> assign(:total_refs, total_refs)
  end

  defp variable_block?(%{variable_name: nil}), do: false
  defp variable_block?(%{variable_name: ""}), do: false
  defp variable_block?(%{is_constant: true}), do: false
  defp variable_block?(%{type: type}) when type in ~w(divider reference), do: false
  defp variable_block?(%{deleted_at: d}) when not is_nil(d), do: false
  defp variable_block?(_), do: true

  # -- Function Components --

  attr :block, :map, required: true
  attr :sheet, :map, required: true
  attr :usage, :map, default: nil
  attr :workspace_slug, :string, required: true
  attr :project_slug, :string, required: true

  defp variable_block_usage(assigns) do
    has_usage =
      assigns.usage != nil and
        (assigns.usage.reads != [] or assigns.usage.writes != [])

    assigns = assign(assigns, :has_usage, has_usage)

    ~H"""
    <div :if={@has_usage} class="rounded-lg border border-base-300/50 p-3">
      <div class="flex items-center gap-2 mb-2">
        <span class="font-medium text-sm">{label_for_block(@block)}</span>
        <code class="text-xs text-base-content/50">{@sheet.shortcut}.{@block.variable_name}</code>
        <span class="badge badge-xs badge-ghost">{@block.type}</span>
      </div>

      <%!-- Writes --%>
      <div :if={@usage.writes != []} class="mb-2">
        <span class="text-xs font-semibold text-warning flex items-center gap-1 mb-1">
          <.icon name="pencil" class="size-3" />
          {dgettext("sheets", "Modified by")}
        </span>
        <div class="ml-4 space-y-0.5">
          <.usage_ref_row
            :for={ref <- @usage.writes}
            ref={ref}
            block={@block}
            sheet={@sheet}
            workspace_slug={@workspace_slug}
            project_slug={@project_slug}
          />
        </div>
      </div>

      <%!-- Reads --%>
      <div :if={@usage.reads != []}>
        <span class="text-xs font-semibold text-info flex items-center gap-1 mb-1">
          <.icon name="eye" class="size-3" />
          {dgettext("sheets", "Read by")}
        </span>
        <div class="ml-4 space-y-0.5">
          <.usage_ref_row
            :for={ref <- @usage.reads}
            ref={ref}
            block={@block}
            sheet={@sheet}
            workspace_slug={@workspace_slug}
            project_slug={@project_slug}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :ref, :map, required: true
  attr :block, :map, required: true
  attr :sheet, :map, required: true
  attr :workspace_slug, :string, required: true
  attr :project_slug, :string, required: true

  defp usage_ref_row(%{ref: %{source_type: "scene_zone"}} = assigns) do
    detail = format_zone_ref_detail(assigns.ref)
    assigns = assign(assigns, :detail, detail)

    ~H"""
    <.link
      navigate={~p"/workspaces/#{@workspace_slug}/projects/#{@project_slug}/scenes/#{@ref.scene_id}"}
      class="flex items-center gap-2 text-xs hover:text-primary group py-0.5"
    >
      <.icon name="map" class="size-3 text-base-content/40 group-hover:text-primary" />
      <span class="font-medium">{@ref.scene_name}</span>
      <.icon name="arrow-right" class="size-3 text-base-content/40" />
      <span class="badge badge-xs badge-ghost">{@ref.zone_name}</span>
      <span :if={@detail} class="text-base-content/40">{@detail}</span>
      <.stale_badge :if={@ref[:stale]} />
    </.link>
    """
  end

  defp usage_ref_row(assigns) do
    detail = format_ref_detail(assigns.ref, assigns.sheet, assigns.block)
    assigns = assign(assigns, :detail, detail)

    ~H"""
    <.link
      navigate={
        ~p"/workspaces/#{@workspace_slug}/projects/#{@project_slug}/flows/#{@ref.flow_id}?node=#{@ref.node_id}"
      }
      class="flex items-center gap-2 text-xs hover:text-primary group py-0.5"
    >
      <.icon
        name={icon_for_node_type(@ref.node_type)}
        class="size-3 text-base-content/40 group-hover:text-primary"
      />
      <span class="font-medium">{@ref.flow_name}</span>
      <.icon name="arrow-right" class="size-3 text-base-content/40" />
      <span class="badge badge-xs badge-ghost">{@ref.node_type}</span>
      <span :if={@detail} class="text-base-content/40">{@detail}</span>
      <.stale_badge :if={@ref[:stale]} />
    </.link>
    """
  end

  defp stale_badge(assigns) do
    ~H"""
    <span
      class="badge badge-xs badge-warning gap-1"
      title={dgettext("sheets", "Reference may be outdated")}
    >
      <.icon name="alert-triangle" class="size-3" />
      {dgettext("sheets", "Outdated")}
    </span>
    """
  end

  # -- Helpers --

  defp label_for_block(block) do
    get_in(block.config, ["label"]) || block.variable_name
  end

  defp icon_for_node_type("instruction"), do: "zap"
  defp icon_for_node_type("condition"), do: "git-branch"
  defp icon_for_node_type(_), do: "circle"

  defp format_zone_ref_detail(ref) when ref.kind == "write" do
    assignments = (ref.zone_action_data || %{})["assignments"] || []

    matching =
      Enum.find(assignments, fn a ->
        a["sheet"] == ref.source_sheet and a["variable"] == ref.source_variable
      end)

    if matching, do: format_assignment_detail(matching)
  end

  defp format_zone_ref_detail(_ref), do: nil

  defp format_ref_detail(ref, _sheet, _block) when ref.kind == "write" do
    assignments = ref.node_data["assignments"] || []

    matching =
      Enum.find(assignments, fn a ->
        a["sheet"] == ref.source_sheet and a["variable"] == ref.source_variable
      end)

    if matching, do: format_assignment_detail(matching)
  end

  defp format_ref_detail(_ref, _sheet, _block), do: nil

  defp format_assignment_detail(%{"operator" => "set", "value" => v, "value_type" => "literal"})
       when is_binary(v),
       do: "= #{v}"

  defp format_assignment_detail(%{"operator" => "add", "value" => v, "value_type" => "literal"})
       when is_binary(v),
       do: "+= #{v}"

  defp format_assignment_detail(%{
         "operator" => "subtract",
         "value" => v,
         "value_type" => "literal"
       })
       when is_binary(v),
       do: "-= #{v}"

  defp format_assignment_detail(%{"operator" => "set_true"}), do: "= true"
  defp format_assignment_detail(%{"operator" => "set_false"}), do: "= false"
  defp format_assignment_detail(%{"operator" => "toggle"}), do: "toggle"
  defp format_assignment_detail(%{"operator" => "clear"}), do: "clear"

  defp format_assignment_detail(%{
         "operator" => op,
         "value_type" => "variable_ref",
         "value_sheet" => vp,
         "value" => v
       })
       when is_binary(vp) and is_binary(v) do
    op_label =
      case op do
        "set" -> "="
        "add" -> "+="
        "subtract" -> "-="
        _ -> "="
      end

    "#{op_label} #{vp}.#{v}"
  end

  defp format_assignment_detail(_), do: nil
end
