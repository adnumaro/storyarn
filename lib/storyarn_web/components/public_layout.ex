defmodule StoryarnWeb.Components.PublicLayout do
  @moduledoc """
  LiveVue layout boundary for public marketing and invitation pages.

  The route/controller owns page data and actions. This wrapper only serializes
  public navigation state and mounts the Vue layout boundary.
  """

  use StoryarnWeb, :html

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :theme, :string,
    default: nil,
    doc: "optional theme override ('dark' forces dark mode on the public layout subtree)"

  attr :native, :boolean,
    default: false,
    doc: "renders the slot as server HTML inside the public shell instead of a LiveVue injection"

  slot :inner_block, required: true

  def public(assigns) do
    assigns =
      assigns
      |> assign(:public_layout_urls, public_layout_urls())
      |> assign(:public_layout_signed_in, signed_in?(assigns.current_scope))

    ~H"""
    <div id="public-layout-wrapper">
      <%= if @native do %>
        <div class={[
          "flex min-h-screen w-full flex-col bg-background text-foreground",
          @theme == "dark" && "dark"
        ]}>
          <.native_public_header
            urls={@public_layout_urls}
            signed_in={@public_layout_signed_in}
          />
          <main class="flex flex-1 flex-col">
            {render_slot(@inner_block)}
          </main>
          <.native_public_footer />
        </div>
      <% else %>
        <.vue
          v-component="live/layouts/public/Layout"
          v-socket={@socket}
          id="public-layout"
          theme={@theme}
          urls={@public_layout_urls}
          is-logged-in={@public_layout_signed_in}
        />

        {render_slot(@inner_block)}
      <% end %>

      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  defp signed_in?(%{user: user}) when not is_nil(user), do: true
  defp signed_in?(_current_scope), do: false

  attr :urls, :map, required: true
  attr :signed_in, :boolean, required: true

  defp native_public_header(assigns) do
    ~H"""
    <header class="fixed top-5 left-1/2 z-[120] flex h-16 w-[min(calc(100%-48px),1280px)] -translate-x-1/2 items-center rounded-full border border-border bg-background/80 px-5 shadow-[0_20px_80px_rgba(0,0,0,0.28)] backdrop-blur-xl">
      <.link navigate={@urls.home} class="flex shrink-0 items-center" aria-label="Storyarn home">
        <img src={~p"/images/logos/logo-name-white.png"} alt="Storyarn" class="h-10.5 w-auto" />
      </.link>

      <nav class="ml-8 hidden items-center gap-1 xl:flex" aria-label="Primary navigation">
        <a href="/#features-section" class="btn btn-ghost btn-sm font-medium">Features</a>
        <a href="/#discover" class="btn btn-ghost btn-sm font-medium">Discover</a>
        <.link navigate={@urls.docs} class="btn btn-ghost btn-sm font-medium">Docs</.link>
        <.link navigate={@urls.blog} class="btn btn-ghost btn-sm font-medium">Blog</.link>
        <.link navigate={@urls.contact} class="btn btn-ghost btn-sm font-medium">Contact</.link>
      </nav>

      <div class="ml-auto hidden items-center gap-2 xl:flex">
        <%= if @signed_in do %>
          <.link navigate={@urls.workspaces} class="btn btn-ghost btn-sm">Dashboard</.link>
        <% else %>
          <a href="/#waitlist" class="btn btn-primary btn-sm rounded-full px-5">Request access</a>
          <.link navigate={@urls.login} class="btn btn-ghost btn-sm">Log in</.link>
        <% end %>
      </div>

      <details class="dropdown dropdown-end ml-auto xl:hidden">
        <summary
          id="public-mobile-menu"
          class="btn btn-ghost btn-square btn-sm list-none"
          aria-label="Open navigation"
        >
          <.icon name="menu" class="size-5" />
        </summary>
        <ul class="menu dropdown-content z-[130] mt-3 w-64 rounded-2xl border border-border bg-background p-3 shadow-2xl">
          <li><a href="/#features-section"><.icon name="sparkles" class="size-4" /> Features</a></li>
          <li><a href="/#discover"><.icon name="panels-top-left" class="size-4" /> Discover</a></li>
          <li><.link navigate={@urls.docs}><.icon name="book-open" class="size-4" /> Docs</.link></li>
          <li><.link navigate={@urls.blog}><.icon name="newspaper" class="size-4" /> Blog</.link></li>
          <li>
            <.link navigate={@urls.contact}><.icon name="mail" class="size-4" /> Contact</.link>
          </li>
          <li class="mt-2 border-t border-border pt-2">
            <%= if @signed_in do %>
              <.link navigate={@urls.workspaces}>Dashboard</.link>
            <% else %>
              <a href="/#waitlist">Request access</a>
              <.link navigate={@urls.login}>Log in</.link>
            <% end %>
          </li>
        </ul>
      </details>
    </header>
    """
  end

  defp native_public_footer(assigns) do
    ~H"""
    <footer class="border-t border-border/40 bg-[#111318] px-6 py-10">
      <div class="mx-auto flex w-full max-w-7xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <img
            src={~p"/images/logos/logo-name-white.png"}
            alt="Storyarn"
            class="h-7 w-auto opacity-90"
          />
          <p class="mt-3 max-w-xl text-sm text-muted-foreground">
            A connected workspace for narrative design, worldbuilding, testing, localization, and export.
          </p>
        </div>
        <nav
          class="flex flex-wrap gap-x-5 gap-y-3 text-sm text-muted-foreground"
          aria-label="Footer navigation"
        >
          <.link navigate={~p"/docs"} class="transition-colors hover:text-foreground">Docs</.link>
          <.link navigate={~p"/blog"} class="transition-colors hover:text-foreground">Blog</.link>
          <.link navigate={~p"/contact"} class="transition-colors hover:text-foreground">
            Contact
          </.link>
          <.link navigate={~p"/privacy"} class="transition-colors hover:text-foreground">
            Privacy
          </.link>
          <.link navigate={~p"/terms"} class="transition-colors hover:text-foreground">Terms</.link>
        </nav>
      </div>
    </footer>
    """
  end

  defp public_layout_urls do
    %{
      home: ~p"/",
      docs: ~p"/docs",
      blog: ~p"/blog",
      contact: ~p"/contact",
      login: ~p"/users/log-in",
      workspaces: ~p"/workspaces"
    }
  end
end
