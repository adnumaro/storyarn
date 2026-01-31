defmodule StoryarnWeb.TreeComponents do
  @moduledoc """
  Tree components for hierarchical navigation (Notion-style).
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.CoreComponents

  @doc """
  Renders a collapsible tree node with optional children.

  ## Examples

      <.tree_node
        id="characters"
        label="Characters"
        icon="hero-user"
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
  attr :color, :string, default: nil
  attr :badge, :any, default: nil
  attr :expanded, :boolean, default: false
  attr :has_children, :boolean, default: false
  attr :class, :string, default: ""
  slot :inner_block

  def tree_node(assigns) do
    ~H"""
    <div class={["tree-node", @class]}>
      <div class="flex items-center">
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
            <.icon name="hero-chevron-right" class="size-3" />
          </span>
        </button>
        <span :if={!@has_children} class="w-5 shrink-0"></span>

        <%!-- Node content (clickable if has href) --%>
        <%= if @href do %>
          <.link
            navigate={@href}
            class="flex-1 flex items-center gap-2 px-2 py-1 rounded hover:bg-base-300 text-sm truncate"
          >
            <span :if={@icon_text} class="shrink-0">{@icon_text}</span>
            <.icon
              :if={@icon && !@icon_text}
              name={@icon}
              class="size-4 shrink-0"
              style={@color && "color: #{@color}"}
            />
            <span class="truncate">{@label}</span>
            <span :if={@badge} class="badge badge-xs badge-ghost ml-auto shrink-0">{@badge}</span>
          </.link>
        <% else %>
          <div class="flex-1 flex items-center gap-2 px-2 py-1 text-sm truncate">
            <span :if={@icon_text} class="shrink-0">{@icon_text}</span>
            <.icon
              :if={@icon && !@icon_text}
              name={@icon}
              class="size-4 shrink-0"
              style={@color && "color: #{@color}"}
            />
            <span class="truncate">{@label}</span>
            <span :if={@badge} class="badge badge-xs badge-ghost ml-auto shrink-0">{@badge}</span>
          </div>
        <% end %>
      </div>

      <%!-- Children container --%>
      <div
        :if={@has_children}
        id={"tree-content-#{@id}"}
        class={["pl-5", !@expanded && "hidden"]}
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
  attr :color, :string, default: nil
  attr :class, :string, default: ""

  def tree_leaf(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 px-2 py-1 rounded text-sm truncate ml-5",
        @active && "bg-base-300 font-medium",
        !@active && "hover:bg-base-300",
        @class
      ]}
    >
      <span :if={@icon_text} class="shrink-0">{@icon_text}</span>
      <.icon
        :if={@icon && !@icon_text}
        name={@icon}
        class="size-4 shrink-0"
        style={@color && "color: #{@color}"}
      />
      <span :if={!@icon && !@icon_text} class="w-4 h-4 flex items-center justify-center shrink-0">
        <span class="w-1.5 h-1.5 rounded-full bg-base-content/30"></span>
      </span>
      <span class="truncate">{@label}</span>
    </.link>
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
        icon="hero-cog-6-tooth"
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
