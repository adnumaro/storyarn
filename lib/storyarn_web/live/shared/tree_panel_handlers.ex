defmodule StoryarnWeb.Live.Shared.TreePanelHandlers do
  @moduledoc """
  Shared event handlers for the focus layout tree panel.

  Import this module in any LiveView that uses `Layouts.focus` to get
  tree panel toggle, pin, and tool switching event handlers.

  ## Usage

      import StoryarnWeb.Live.Shared.TreePanelHandlers

  Then delegate in `handle_event/3`:

      def handle_event("tree_panel_" <> _ = event, params, socket),
        do: handle_tree_panel_event(event, params, socket)

      def handle_event("switch_tool", params, socket),
        do: handle_tree_panel_event("switch_tool", params, socket)

      def handle_event("tree_panel_init", params, socket),
        do: handle_tree_panel_event("tree_panel_init", params, socket)

  ## Required assigns

  The socket must have these assigns set in mount:
  - `:tree_panel_open` (boolean)
  - `:tree_panel_pinned` (boolean)
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Handles tree panel events. Call from your LiveView's handle_event/3.
  """
  def handle_tree_panel_event("tree_panel_init", %{"pinned" => pinned}, socket) do
    # The JS hook tells us the localStorage-persisted pin state.
    # Only sync the pinned assign — don't touch tree_panel_open,
    # since the panel is already open if this hook mounted.
    {:noreply, assign(socket, :tree_panel_pinned, pinned)}
  end

  def handle_tree_panel_event("tree_panel_toggle", _params, socket) do
    open = !socket.assigns.tree_panel_open

    {:noreply, assign(socket, :tree_panel_open, open)}
  end

  def handle_tree_panel_event("tree_panel_pin", _params, socket) do
    pinned = !socket.assigns.tree_panel_pinned

    # Unpinning closes the panel; pinning keeps it as-is
    open = if pinned, do: socket.assigns.tree_panel_open, else: false

    {:noreply,
     socket
     |> assign(:tree_panel_pinned, pinned)
     |> assign(:tree_panel_open, open)}
  end

  @doc """
  Returns default focus layout assigns to merge in mount.

  ## Example

      socket
      |> assign(focus_layout_defaults())
      |> assign(:active_tool, :sheets)
  """
  def focus_layout_defaults do
    [
      tree_panel_open: true,
      tree_panel_pinned: true,
      online_users: []
    ]
  end
end
