defmodule StoryarnWeb.Components.PublicLayout do
  @moduledoc """
  Shared shell for public marketing, blog, legal, and invitation pages.

  The route owns its page content and actions. This wrapper owns the single
  public header/footer pair and keeps server-rendered content inside the same
  shell as LiveVue pages.
  """

  use StoryarnWeb, :html

  alias StoryarnWeb.Components.PublicFooter
  alias StoryarnWeb.Components.PublicHeader

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"
  attr :seo_metadata, :map, required: true, doc: "metadata synchronized into the document head"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :theme, :string,
    default: nil,
    doc: "optional theme override ('dark' forces dark mode on the public layout subtree)"

  attr :landing, :boolean,
    default: false,
    doc: "whether the current route owns the landing-page section anchors"

  slot :inner_block, required: true

  def public(assigns) do
    assigns =
      assigns
      |> assign(:public_layout_urls, public_layout_urls())
      |> assign(:public_layout_signed_in, signed_in?(assigns.current_scope))

    ~H"""
    <div
      id="public-layout-wrapper"
      class={[
        "flex min-h-screen w-full flex-col bg-background text-foreground",
        @theme == "dark" && "dark"
      ]}
    >
      <Layouts.live_seo metadata={@seo_metadata} />
      <PublicHeader.header
        dark={@theme == "dark"}
        landing={@landing}
        signed_in={@public_layout_signed_in}
        urls={@public_layout_urls}
      />

      <main id="public-main" class="flex min-h-0 flex-1 flex-col">
        {render_slot(@inner_block)}
      </main>

      <PublicFooter.footer
        landing={@landing}
        urls={@public_layout_urls}
      />

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  defp signed_in?(%{user: user}) when not is_nil(user), do: true
  defp signed_in?(_current_scope), do: false

  defp public_layout_urls do
    %{
      home: ~p"/",
      docs: ~p"/docs",
      blog: ~p"/blog",
      contact: ~p"/contact",
      privacy: ~p"/privacy",
      terms: ~p"/terms",
      login: ~p"/users/log-in",
      register: ~p"/users/register",
      workspaces: ~p"/workspaces"
    }
  end
end
