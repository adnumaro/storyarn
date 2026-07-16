defmodule StoryarnWeb.Components.AuthLayout do
  @moduledoc """
  LiveVue layout boundary for authentication pages.

  Auth page LiveViews own form state and actions. This wrapper mounts the
  public Vue layout boundary and keeps flash rendering outside the injected
  page content.
  """

  use StoryarnWeb, :html

  alias Storyarn.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.PublicURLs

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"
  attr :seo_metadata, :map, required: true, doc: "metadata synchronized into the document head"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def auth(assigns) do
    robots = Map.get(assigns.seo_metadata, :robots) || "noindex, follow"
    locale = assigns.seo_metadata |> Map.get(:content_locale) |> PublicLocales.normalize()

    assigns =
      assigns
      |> assign(:locale, locale)
      |> assign(:seo_metadata, Map.put(assigns.seo_metadata, :robots, robots))

    ~H"""
    <div id="auth-layout-wrapper" class="min-h-screen bg-background text-foreground">
      <Layouts.live_seo metadata={@seo_metadata} />
      <.vue
        v-component="live/layouts/auth/Layout"
        v-socket={@socket}
        id="auth-layout"
        home-url={PublicURLs.home_path(@locale)}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group
        flash={@flash}
        socket={@socket}
        privacy_url={PublicURLs.privacy_path(@locale) <> "#cookies"}
        terms_url={PublicURLs.terms_path(@locale)}
      />
    </div>
    """
  end
end
