defmodule StoryarnWeb.Components.PublicLayout do
  @moduledoc """
  LiveVue layout boundary for public marketing and invitation pages.

  The route/controller owns page data and actions. This wrapper only serializes
  public navigation state and mounts the Vue layout boundary.
  """

  use StoryarnWeb, :html

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :theme, :string,
    default: nil,
    doc: "optional theme override ('dark' forces dark mode on the public layout subtree)"

  slot :inner_block, required: true

  def public(assigns) do
    assigns =
      assigns
      |> assign(:public_layout_urls, public_layout_urls())
      |> assign(:public_layout_signed_in, signed_in?(assigns.current_scope))

    ~H"""
    <div id="public-layout-wrapper">
      <.vue
        v-component="live/layouts/public/Layout"
        id="public-layout"
        theme={@theme}
        urls={@public_layout_urls}
        is-logged-in={@public_layout_signed_in}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp signed_in?(%{user: user}) when not is_nil(user), do: true
  defp signed_in?(_current_scope), do: false

  defp public_layout_urls do
    %{
      home: ~p"/",
      docs: ~p"/docs",
      contact: ~p"/contact",
      login: ~p"/users/log-in",
      workspaces: ~p"/workspaces"
    }
  end
end
