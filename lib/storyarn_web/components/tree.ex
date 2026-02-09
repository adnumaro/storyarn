defmodule StoryarnWeb.Components.TreeComponents do
  @moduledoc """
  Tree components for hierarchical navigation (Notion-style).
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  @doc """
  Renders a collapsible tree node with optional children.

  ## Examples

      <.tree_node
        id="characters"
        label="Characters"
        icon="user"
        color="#3b82f6"
        badge={3}
        expanded={true}
      >
        <.tree_leaf label="John Doe" href={~p"/entities/1"} />
        <.tree_leaf label="Sarah" href={~p"/entities/2"} />
      </.tree_node>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :href, :string, default: nil
  attr :icon, :string, default: nil
  attr :icon_text, :string, default: nil
  attr :avatar_url, :string, default: nil
  attr :color, :string, default: nil
  attr :badge, :any, default: nil
  attr :expanded, :boolean, default: false
  attr :has_children, :boolean, default: false
  attr :class, :string, default: ""
  attr :item_id, :string, default: nil
  attr :item_name, :string, default: nil
  attr :can_drag, :boolean, default: false
  slot :inner_block
  slot :menu
  slot :actions

  def tree_node(assigns) do
    ~H"""
    <div
      class={["tree-node group", @can_drag && "cursor-grab active:cursor-grabbing", @class]}
      data-item-id={@item_id}
      data-item-name={@item_name}
    >
      <div class="relative flex items-center">
        <%!-- Expand/collapse toggle --%>
        <button
          :if={@has_children}
          type="button"
          class="flex items-center justify-center w-5 h-5 hover:bg-base-300 rounded shrink-0"
          phx-hook="TreeToggle"
          id={"tree-toggle-#{@id}"}
          data-node-id={@id}
        >
          <span
            class={[
              "transition-transform duration-200",
              @expanded && "rotate-90"
            ]}
            data-chevron
          >
            <.icon name="chevron-right" class="size-3" />
          </span>
        </button>
        <span :if={!@has_children} class="w-5 shrink-0"></span>

        <%!-- Node content (clickable if has href) --%>
        <%= if @href do %>
          <.link
            navigate={@href}
            class="flex-1 flex items-center gap-2 px-2 py-1 rounded hover:bg-base-300 text-sm truncate"
          >
            <.tree_icon icon={@icon} icon_text={@icon_text} avatar_url={@avatar_url} color={@color} />
            <span class="truncate">{@label}</span>
            <span :if={@badge} class="badge badge-xs badge-ghost ml-auto shrink-0">{@badge}</span>
          </.link>
        <% else %>
          <div class="flex-1 flex items-center gap-2 px-2 py-1 text-sm truncate">
            <.tree_icon icon={@icon} icon_text={@icon_text} avatar_url={@avatar_url} color={@color} />
            <span class="truncate">{@label}</span>
            <span :if={@badge} class="badge badge-xs badge-ghost ml-auto shrink-0">{@badge}</span>
          </div>
        <% end %>

        <%!-- Actions slot (+ button and menu) --%>
        <div
          :if={@actions != [] || @menu != []}
          class="absolute right-0 flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
        >
          {render_slot(@actions)}
          {render_slot(@menu)}
        </div>
      </div>

      <%!-- Children container --%>
      <div
        :if={@has_children}
        id={"tree-content-#{@id}"}
        class={["pl-5", !@expanded && "hidden"]}
        data-sortable-container
        data-parent-id={@item_id}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a tree leaf (clickable item without children).

  ## Examples

      <.tree_leaf
        label="John Doe"
        href={~p"/projects/1/entities/123"}
        active={true}
      />
  """
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, default: nil
  attr :icon_text, :string, default: nil
  attr :avatar_url, :string, default: nil
  attr :color, :string, default: nil
  attr :class, :string, default: ""
  attr :item_id, :string, default: nil
  attr :item_name, :string, default: nil
  attr :can_drag, :boolean, default: false
  slot :menu
  slot :actions

  def tree_leaf(assigns) do
    ~H"""
    <div
      class={["tree-leaf group", @can_drag && "cursor-grab active:cursor-grabbing", @class]}
      data-item-id={@item_id}
      data-item-name={@item_name}
    >
      <div class="relative flex items-center">
        <%!-- Spacer to align with tree_node (expand/collapse area) --%>
        <span class="w-5 shrink-0"></span>

        <.link
          navigate={@href}
          class={[
            "flex-1 flex items-center gap-2 px-2 py-1 rounded text-sm truncate",
            @active && "bg-base-300 font-medium",
            !@active && "hover:bg-base-300"
          ]}
        >
          <.tree_icon icon={@icon} icon_text={@icon_text} avatar_url={@avatar_url} color={@color} />
          <span class="truncate">{@label}</span>
        </.link>
        <div
          :if={@actions != [] || @menu != []}
          class="absolute right-0 flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
        >
          {render_slot(@actions)}
          {render_slot(@menu)}
        </div>
      </div>
    </div>
    """
  end

  attr :icon, :string, default: nil
  attr :icon_text, :string, default: nil
  attr :avatar_url, :string, default: nil
  attr :color, :string, default: nil

  defp tree_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @avatar_url -> %>
        <img src={@avatar_url} alt="" class="size-4 shrink-0 rounded object-cover" />
      <% @icon_text && @icon_text not in [nil, "", "sheet"] -> %>
        <span class="shrink-0">{@icon_text}</span>
      <% @icon -> %>
        <.icon name={@icon} class="size-4 shrink-0" style={@color && "color: #{@color}"} />
      <% true -> %>
        <.icon name="file" class="size-4 shrink-0 opacity-60" />
    <% end %>
    """
  end

  @doc """
  Renders a tree section header.

  ## Examples

      <.tree_section label="ENTITIES" />
  """
  attr :label, :string, required: true
  attr :class, :string, default: ""

  def tree_section(assigns) do
    ~H"""
    <div class={[
      "text-xs font-semibold uppercase text-base-content/50 px-2 py-2 tracking-wide",
      @class
    ]}>
      {@label}
    </div>
    """
  end

  @doc """
  Renders a tree navigation link (for non-hierarchical items like Settings).

  ## Examples

      <.tree_link
        label="Settings"
        href={~p"/projects/1/settings"}
        icon="settings"
        active={true}
      />
  """
  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, default: nil
  attr :active, :boolean, default: false
  attr :class, :string, default: ""

  def tree_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 px-2 py-1.5 rounded text-sm",
        @active && "bg-base-300 font-medium",
        !@active && "hover:bg-base-300",
        @class
      ]}
    >
      <.icon :if={@icon} name={@icon} class="size-4" />
      <span>{@label}</span>
    </.link>
    """
  end
end
