defmodule StoryarnWeb.Components.AuthLayout do
  @moduledoc """
  LiveVue layout boundary for authentication pages.

  Auth page LiveViews own form state and actions. This wrapper mounts the
  public Vue layout boundary and keeps flash rendering outside the injected
  page content.
  """

  use StoryarnWeb, :html

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div id="auth-layout-wrapper">
      <.vue v-component="live/layouts/auth/Layout" v-socket={@socket} id="auth-layout" />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end
end
