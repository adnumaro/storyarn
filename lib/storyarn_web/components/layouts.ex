defmodule StoryarnWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.UIComponents, only: [theme_toggle: 1]
  import StoryarnWeb.DocsLive.Components.DocsSidebar

  alias Phoenix.LiveView.JS

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  attr :class, :string, default: "w-8 h-8"

  defp app_logo(assigns) do
    ~H"""
    <img src={~p"/images/logos/logo-black-48.png"} alt="Storyarn" class={[@class, "dark:hidden"]} />
    <img
      src={~p"/images/logos/logo-white-48.png"}
      alt="Storyarn"
      class={[@class, "hidden dark:block"]}
    />
    """
  end

  # App layout — delegates to AppLayout module (Vue + shadcn-vue)
  defdelegate app(assigns), to: StoryarnWeb.Components.AppLayout

  # Workspace layout — static sidebar layout for workspaces dashboard
  defdelegate workspace(assigns), to: StoryarnWeb.Components.WorkspaceLayout

  @doc """
  Renders a chromeless canvas layout for version comparison mode.

  No project menu, tool switcher, or user menu. Optional collapsible
  side panel for layer controls or similar content. Always canvas mode.

  ## Examples

      <Layouts.compare flash={@flash} panel_title="Layers" panel_open={@main_sidebar_open}>
        <:panel>
          Layer controls here
        </:panel>
        Canvas content here
      </Layouts.compare>
  """
  attr :flash, :map, required: true
  attr :panel_title, :string, default: nil, doc: "title shown in the side panel header"
  attr :panel_open, :boolean, default: true, doc: "whether the side panel is open"

  slot :panel, doc: "optional side panel content (e.g. layer controls)"
  slot :inner_block, required: true

  def compare(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden relative bg-background">
      <%!-- Floating button to reopen panel when collapsed --%>
      <button
        :if={@panel != [] && !@panel_open}
        type="button"
        phx-click="main_sidebar_toggle"
        class="fixed top-3 left-3 z-[1020] surface-panel p-1"
        title={gettext("Show panel")}
      >
        <span class="inline-flex items-center justify-center size-8 rounded-md hover:bg-accent transition-colors">
          <.icon name="panel-left" class="size-4" />
        </span>
      </button>

      <%!-- Collapsible side panel --%>
      <div
        :if={@panel != []}
        id="compare-panel"
        class={[
          "fixed left-3 top-3 bottom-3 z-[1010] w-52 flex flex-col surface-panel overflow-hidden",
          "transition-all duration-200",
          if(@panel_open,
            do: "translate-x-0 opacity-100",
            else: "-translate-x-[calc(100%+0.75rem)] opacity-0 pointer-events-none"
          )
        ]}
      >
        <%!-- Panel header with title + collapse button --%>
        <div class="flex items-center justify-between px-2.5 py-2 border-b border-border">
          <span
            :if={@panel_title}
            class="text-xs font-medium text-muted-foreground flex items-center gap-1.5"
          >
            {@panel_title}
          </span>
          <button
            type="button"
            phx-click="main_sidebar_toggle"
            class="inline-flex items-center justify-center size-7 rounded-md hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
            title={gettext("Close panel")}
          >
            <.icon name="panel-left-close" class="size-3.5" />
          </button>
        </div>

        <%!-- Panel content (scrollable) --%>
        <div class="flex-1 overflow-y-auto p-2">
          {render_slot(@panel)}
        </div>
      </div>

      <%!-- Main content area (always canvas mode) --%>
      <main id="main-content" class="h-full overflow-hidden">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a centered layout without sidebar for auth sheets.

  ## Examples

      <Layouts.auth flash={@flash}>
        <h1>Login</h1>
      </Layouts.auth>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate="/" class="flex items-center gap-2">
            <.app_logo class="w-8 h-8" />
            <span class="text-xl brand-logotype">Storyarn</span>
          </.link>
        </div>
      </header>

      <main class="flex-1 flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8">
        <div class="w-full max-w-md space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a simple centered layout for public sheets.

  ## Examples

      <Layouts.public flash={@flash}>
        <h1>Welcome</h1>
      </Layouts.public>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :theme, :string,
    default: nil,
    doc: "optional theme override ('dark' forces dark mode on the public layout subtree)"

  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class={[
      "min-h-screen flex flex-col w-full bg-background text-foreground",
      @theme == "dark" && "dark"
    ]}>
      <header
        class={[
          "w-[min(calc(100%-48px),1280px)] h-16 flex items-center",
          @theme == "dark" &&
            "z-[120] rounded-full border border-border bg-background/70 px-5 backdrop-blur-xl shadow-[0_20px_80px_rgba(0,0,0,0.28)]"
        ]}
        style={
          @theme == "dark" &&
            "position: fixed; top: 1.25rem; left: 50%; transform: translateX(-50%);"
        }
      >
        <div class="flex w-full items-center gap-4 px-4 sm:px-5 lg:px-6">
          <div class="flex-none">
            <.link navigate="/" class="flex items-center">
              <img
                src={~p"/images/logos/logo-name-black.png"}
                alt="Storyarn"
                class="h-[42px] w-auto dark:hidden"
              />
              <img
                src={~p"/images/logos/logo-name-white.png"}
                alt="Storyarn"
                class="hidden h-[42px] w-auto dark:block"
              />
            </.link>
          </div>
          <%!-- Desktop nav --%>
          <div class="hidden min-w-0 flex-1 items-center justify-between gap-6 xl:flex">
            <div class="flex min-w-0 items-center gap-2">
              <a
                href="#features"
                onclick="window.dispatchEvent(new CustomEvent('storyarn:force-scroll', { detail: { panelIndex: 1 } })); return false;"
                class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
              >
                {gettext("Features")}
              </a>
              <a
                href="#discover"
                onclick="window.dispatchEvent(new CustomEvent('storyarn:force-scroll', { detail: { panelIndex: 2 } })); return false;"
                class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
              >
                {gettext("Discover")}
              </a>
              <.link
                navigate={~p"/docs"}
                class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
              >
                {gettext("Docs")}
              </.link>
              <.link
                navigate={~p"/contact"}
                class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
              >
                {gettext("Contact")}
              </.link>
            </div>
            <div class="flex flex-none items-center gap-2">
              <%= if @current_scope && @current_scope.user do %>
                <.link
                  navigate={~p"/workspaces"}
                  class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
                >
                  {gettext("Dashboard")}
                </.link>
              <% else %>
                <a
                  href="#waitlist"
                  onclick="window.dispatchEvent(new CustomEvent('storyarn:force-scroll', { detail: { panelIndex: 3 } })); return false;"
                  class="inline-flex items-center justify-center px-5 py-2.5 text-sm font-bold rounded-md text-teal-950 hover:scale-105 transition-all"
                  style="background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210)); box-shadow: 0 0 20px rgba(34, 211, 238, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.3);"
                >
                  {gettext("Request access")}
                </a>
                <.link
                  navigate={~p"/users/log-in"}
                  class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-medium rounded-md hover:bg-accent text-foreground/80 hover:text-foreground transition-colors"
                >
                  {gettext("Log in")}
                </.link>
              <% end %>
            </div>
          </div>
          <%!-- Mobile hamburger --%>
          <div class="ml-auto flex-none xl:hidden">
            <button
              phx-click={JS.toggle(to: "#mobile-nav", in: "fade-in", out: "fade-out")}
              class="inline-flex items-center justify-center size-8 rounded-md hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
              aria-label={gettext("Menu")}
            >
              <.icon name="menu" class="size-5" />
            </button>
          </div>
        </div>
      </header>

      <%!-- Mobile nav overlay --%>
      <nav
        id="mobile-nav"
        class={[
          "hidden fixed inset-0 z-[140] w-screen max-w-none xl:hidden",
          @theme == "dark" && "bg-background/96 backdrop-blur-xl"
        ]}
        style="z-index: 140;"
        phx-click-away={JS.hide(to: "#mobile-nav", transition: "fade-out")}
      >
        <div class="flex min-h-screen">
          <aside class="flex min-h-screen w-full justify-center bg-background/98 px-5 pb-8 pt-5">
            <div class="flex min-h-full w-full max-w-[420px] flex-col">
              <div class="flex items-center justify-between gap-4">
                <.link navigate="/" class="flex items-center text-foreground">
                  <img
                    src={~p"/images/logos/logo-name-black.png"}
                    alt="Storyarn"
                    class="h-[42px] w-auto dark:hidden"
                  />
                  <img
                    src={~p"/images/logos/logo-name-white.png"}
                    alt="Storyarn"
                    class="hidden h-[42px] w-auto dark:block"
                  />
                </.link>
                <button
                  phx-click={JS.hide(to: "#mobile-nav", transition: "fade-out")}
                  class="inline-flex items-center justify-center size-8 rounded-md hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
                  aria-label={gettext("Close")}
                >
                  <.icon name="x" class="size-5" />
                </button>
              </div>

              <div class="mt-8 grid gap-2">
                <a
                  href="#features"
                  class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                  phx-click={
                    JS.hide(to: "#mobile-nav", transition: "fade-out")
                    |> JS.dispatch("storyarn:force-scroll", detail: %{panelIndex: 1})
                  }
                >
                  <.icon name="sparkles" class="size-5 text-foreground/45" />
                  {gettext("Features")}
                </a>
                <a
                  href="#discover"
                  class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                  phx-click={
                    JS.hide(to: "#mobile-nav", transition: "fade-out")
                    |> JS.dispatch("storyarn:force-scroll", detail: %{panelIndex: 2})
                  }
                >
                  <.icon name="panels-top-left" class="size-5 text-foreground/45" />
                  {gettext("Discover")}
                </a>
                <.link
                  navigate={~p"/docs"}
                  class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                >
                  <.icon name="book-open" class="size-5 text-foreground/45" />
                  {gettext("Docs")}
                </.link>
                <.link
                  navigate={~p"/contact"}
                  class="flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground transition-colors hover:bg-accent"
                >
                  <.icon name="mail" class="size-5 text-foreground/45" />
                  {gettext("Contact")}
                </.link>
              </div>

              <div class="mt-auto grid gap-3 border-t border-border pt-5">
                <%= if @current_scope && @current_scope.user do %>
                  <.link
                    navigate={~p"/workspaces"}
                    class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors btn-block rounded-2xl"
                  >
                    {gettext("Dashboard")}
                  </.link>
                <% else %>
                  <a
                    href="#waitlist"
                    class="inline-flex items-center justify-center px-4 py-2.5 text-sm font-bold rounded-xl text-teal-950 hover:scale-105 transition-all w-full"
                    style="background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210)); box-shadow: 0 0 20px rgba(34, 211, 238, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.3);"
                    onclick="window.dispatchEvent(new CustomEvent('storyarn:force-scroll', { detail: { panelIndex: 3 } })); return false;"
                    phx-click={JS.hide(to: "#mobile-nav", transition: "fade-out")}
                  >
                    {gettext("Request access")}
                  </a>
                  <.link
                    navigate={~p"/users/log-in"}
                    class="inline-flex items-center justify-center px-3 py-2 text-sm rounded-md hover:bg-accent transition-colors btn-block rounded-2xl"
                  >
                    {gettext("Log in")}
                  </.link>
                <% end %>
              </div>
            </div>
          </aside>
        </div>
      </nav>

      <main class="flex-1 flex flex-col">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a fullscreen settings layout with floating toolbars and sidebar.

  Visually consistent with `Layouts.app` — floating surface-panel toolbars
  and sidebar, fullscreen background.

  Accepts optional `back_path`, `back_label`, and `sidebar_sections` to customize
  the sidebar. When not provided, defaults to account/workspace navigation.

  ## Examples

      <Layouts.settings
        flash={@flash}
        current_scope={@current_scope}
        workspaces={@workspaces}
        current_path={@current_path}
      >
        <:title>Profile</:title>
        <:subtitle>Manage your profile</:subtitle>
        <p>Content here</p>
      </Layouts.settings>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, required: true, doc: "the current scope"
  attr :workspaces, :list, default: [], doc: "list of workspaces for settings nav"

  attr :managed_workspace_slugs, :any,
    default: MapSet.new(),
    doc: "MapSet of workspace slugs where user has WorkspaceMembership"

  attr :current_path, :string, required: true, doc: "current settings path for nav highlighting"

  attr :back_path, :string, default: nil, doc: "custom back link path (defaults to /workspaces)"

  attr :back_label, :string,
    default: nil,
    doc: "custom back link label (defaults to 'Back to app')"

  attr :sidebar_sections, :list,
    default: nil,
    doc: "custom sidebar sections list; when nil, uses default account/workspace nav"

  slot :title
  slot :subtitle
  slot :inner_block, required: true

  def settings(assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_back_path, fn -> assigns.back_path || ~p"/workspaces" end)
      |> assign_new(:resolved_back_label, fn ->
        assigns.back_label || gettext("Back to app")
      end)
      |> assign_new(:resolved_sections, fn ->
        assigns.sidebar_sections ||
          settings_sections(assigns.workspaces, assigns.managed_workspace_slugs)
      end)

    ~H"""
    <div
      id="settings-layout"
      class="flex h-screen w-screen overflow-hidden bg-linear-to-br from-background via-background to-muted/40 dark:to-muted/10"
    >
      <%!-- Hidden checkbox for mobile sidebar toggle (must be first child for peer-*) --%>
      <input id="settings-sidebar-check" type="checkbox" class="peer hidden" />

      <%!-- Mobile overlay (closes sidebar on tap) --%>
      <label
        for="settings-sidebar-check"
        class="fixed inset-0 bg-background/80 backdrop-blur-sm z-30 hidden peer-checked:block lg:hidden cursor-pointer"
      />

      <%!-- Mobile header to toggle sidebar --%>
      <div class="absolute top-3 left-3 z-20 lg:hidden">
        <label
          for="settings-sidebar-check"
          class="inline-flex items-center justify-center size-9 rounded-md bg-background border border-border shadow-sm hover:bg-accent transition-colors cursor-pointer text-muted-foreground"
        >
          <.icon name="menu" class="size-5" />
        </label>
      </div>

      <%!-- Settings sidebar (static on desktop, floating on mobile) --%>
      <aside class={[
        "flex-none w-[252px] surface-panel flex flex-col z-40 shrink-0 overflow-hidden rounded-lg",
        "fixed lg:relative top-3 bottom-3 left-3 lg:top-0 lg:bottom-0 lg:left-0 h-[calc(100vh-1.5rem)] lg:h-auto",
        "lg:ml-3 lg:my-3",
        "transition-transform duration-200",
        "-translate-x-[calc(100%+1rem)] peer-checked:translate-x-0 lg:translate-x-0"
      ]}>
        <div class="px-2 pt-3 pb-3 border-b border-border/10">
          <.link
            navigate={@resolved_back_path}
            class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm font-medium text-foreground/70 hover:bg-black/5 hover:text-foreground dark:hover:bg-white/5 transition-colors"
          >
            <.icon name="chevron-left" class="size-4" />
            {@resolved_back_label}
          </.link>
        </div>

        <nav class="flex-1 overflow-y-auto p-3 space-y-5">
          <div :for={section <- @resolved_sections}>
            <h3 class="text-xs font-semibold uppercase text-foreground/50 px-2 mb-2 tracking-wider">
              {section.label}
            </h3>
            <ul class="space-y-0.5">
              <li :for={item <- section.items}>
                <.link
                  navigate={item.path}
                  class={[
                    "flex items-center gap-3 px-2 py-2 rounded-lg text-sm transition-colors",
                    @current_path == item.path &&
                      "bg-black/5 dark:bg-white/10 font-medium text-foreground",
                    @current_path != item.path &&
                      "text-foreground/80 hover:bg-black/5 dark:hover:bg-white/5 hover:text-foreground"
                  ]}
                >
                  <.icon name={item.icon} class="size-4 opacity-70" />
                  {item.label}
                </.link>
              </li>
            </ul>
          </div>
        </nav>
      </aside>

      <%!-- Main content area --%>
      <main class="flex-1 min-w-0 overflow-y-auto bg-background p-4 pt-16 lg:px-8 lg:py-3 min-vh-100">
        <div class="max-w-3xl mx-auto lg:mt-5">
          <header :if={@title != []} class="pb-4">
            <h1 class="text-lg font-semibold leading-8">
              {render_slot(@title)}
            </h1>
            <p :if={@subtitle != []} class="text-sm text-muted-foreground">
              {render_slot(@subtitle)}
            </p>
          </header>

          <div class="mt-8">
            {render_slot(@inner_block)}
          </div>
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp settings_sections(workspaces, managed_workspace_slugs) do
    account_section = %{
      label: gettext("Account"),
      items: [
        %{label: gettext("Profile"), path: ~p"/users/settings", icon: "user"},
        %{
          label: gettext("Security"),
          path: ~p"/users/settings/security",
          icon: "shield-check"
        },
        %{
          label: gettext("Connected accounts"),
          path: ~p"/users/settings/connections",
          icon: "link"
        }
      ]
    }

    # Only show workspaces where user has actual WorkspaceMembership
    managed_workspaces =
      Enum.filter(workspaces, &MapSet.member?(managed_workspace_slugs, &1.slug))

    workspace_sections =
      Enum.map(managed_workspaces, fn workspace ->
        %{
          label: workspace.name,
          items: [
            %{
              label: gettext("General"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/general",
              icon: "settings"
            },
            %{
              label: gettext("Members"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/members",
              icon: "users"
            },
            %{
              label: gettext("Deleted Projects"),
              path: ~p"/users/settings/workspaces/#{workspace.slug}/deleted-projects",
              icon: "trash-2"
            }
          ]
        }
      end)

    [account_section | workspace_sections]
  end

  @doc """
  Renders the documentation layout with sidebar navigation.

  Fully independent — does not depend on any domain context.

  ## Examples

      <Layouts.docs
        flash={@flash}
        categories={@categories}
        guides={@guides}
        guide={@guide}
      >
        <div class="prose">{raw(HtmlSanitizer.sanitize_html(@guide.body))}</div>
      </Layouts.docs>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :categories, :list, required: true
  attr :guides, :list, required: true
  attr :guide, :map, default: nil
  attr :expanded_categories, :any, default: nil
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: nil
  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :sidebar_open, :boolean, default: false

  slot :inner_block, required: true

  def docs(assigns) do
    ~H"""
    <div class="h-screen flex flex-col overflow-hidden">
      <%!-- Header --%>
      <header class="flex items-center h-16 px-4 sm:px-6 lg:px-8 border-b border-border bg-background shrink-0">
        <div class="flex-none lg:hidden mr-4">
          <button
            phx-click="toggle_sidebar"
            class="inline-flex items-center justify-center size-9 rounded-md hover:bg-accent text-muted-foreground transition-colors"
          >
            <.icon name="menu" class="size-5" />
          </button>
        </div>
        <div class="flex-1 flex items-center gap-1">
          <.link href={~p"/"} class="flex items-center gap-2">
            <.app_logo class="w-6 h-6" />
            <span class="text-lg brand-logotype">Storyarn</span>
          </.link>
          <.link
            navigate={~p"/docs"}
            class="text-xs font-medium text-muted-foreground hover:text-foreground transition-colors self-start mt-1"
          >
            {gettext("docs")}
          </.link>
        </div>
        <div class="flex-none flex items-center gap-2">
          <.theme_toggle />
          <%= if @current_scope && @current_scope.user do %>
            <.link
              navigate={~p"/workspaces"}
              class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors"
            >
              {gettext("Dashboard")}
            </.link>
          <% else %>
            <.link
              navigate={~p"/users/log-in"}
              class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors"
            >
              {gettext("Log in")}
            </.link>
          <% end %>
        </div>
      </header>

      <%!-- Main area --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Mobile sidebar overlay --%>
        <div
          :if={@sidebar_open}
          class="fixed inset-0 bg-black/50 z-40 md:hidden"
          phx-click="toggle_sidebar"
        >
        </div>

        <%!-- Sidebar --%>
        <aside class={[
          "w-60 border-r border-border bg-background overflow-y-auto shrink-0",
          "fixed inset-y-0 left-0 z-50 pt-4 transition-transform lg:relative lg:translate-x-0 lg:z-auto lg:pt-6",
          if(@sidebar_open, do: "translate-x-0", else: "-translate-x-full")
        ]}>
          <.docs_sidebar
            categories={@categories}
            guides={@guides}
            guide={@guide}
            expanded_categories={@expanded_categories}
            search_query={@search_query}
            search_results={@search_results}
          />
        </aside>

        <%!-- Content & TOC wrapper --%>
        <main
          id="docs-main"
          class="flex-1 overflow-y-auto xl:flex xl:items-start xl:justify-between px-4 sm:px-8 lg:px-12"
        >
          <%!-- Main content (Centered) --%>
          <div class="flex-1 w-full max-w-4xl mx-auto py-8 min-w-0">
            <%!-- Guide header --%>
            <div :if={@guide} class="mb-8">
              <p class="text-xs uppercase tracking-wider text-primary font-semibold mb-1">
                {@guide.category_label}
              </p>
              <h1 class="text-3xl font-bold">{@guide.title}</h1>
              <p :if={@guide.description} class="text-muted-foreground mt-2">
                {@guide.description}
              </p>
            </div>

            <%!-- Main content --%>
            {render_slot(@inner_block)}

            <%!-- Prev/Next navigation --%>
            <nav
              :if={@prev || @next}
              class="flex items-center justify-between mt-12 pt-8 border-t border-border"
            >
              <div>
                <.link
                  :if={@prev}
                  navigate={~p"/docs/#{@prev.category}/#{@prev.slug}"}
                  class="group flex flex-col items-start"
                >
                  <span class="text-xs text-muted-foreground group-hover:text-muted-foreground">
                    <.icon name="arrow-left" class="size-3 inline" />
                    {gettext("Previous")}
                  </span>
                  <span class="text-sm font-medium text-primary">{@prev.title}</span>
                </.link>
              </div>
              <div>
                <.link
                  :if={@next}
                  navigate={~p"/docs/#{@next.category}/#{@next.slug}"}
                  class="group flex flex-col items-end"
                >
                  <span class="text-xs text-muted-foreground group-hover:text-muted-foreground">
                    {gettext("Next")}
                    <.icon name="arrow-right" class="size-3 inline" />
                  </span>
                  <span class="text-sm font-medium text-primary">{@next.title}</span>
                </.link>
              </div>
            </nav>
          </div>

          <%!-- Table of contents (right rail) --%>
          <aside
            :if={@guide && @guide.toc != []}
            id="docs-toc"
            class="hidden xl:block sticky top-0 w-60 shrink-0 py-8 overflow-y-auto"
            style="max-height: 100vh;"
          >
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
              {gettext("On this page")}
            </p>
            <nav class="border-l border-border">
              <a
                :for={entry <- @guide.toc}
                href={"##{entry.id}"}
                data-toc-id={entry.id}
                class={[
                  "docs-toc-link block text-sm leading-relaxed transition-colors hover:text-primary",
                  if(entry.level == 3, do: "pl-5", else: "pl-3"),
                  "text-muted-foreground"
                ]}
              >
                {entry.text}
              </a>
            </nav>
          </aside>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      data-slot="toaster"
      class="fixed bottom-4 right-4 z-[2000] flex flex-col gap-2 w-full max-w-sm pointer-events-none [&>*]:pointer-events-auto"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-1.5">
          {gettext("Attempting to reconnect")}
          <.icon name="loader-circle" class="size-4 motion-safe:animate-spin" />
        </span>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="flex items-center gap-1.5">
          {gettext("Attempting to reconnect")}
          <.icon name="loader-circle" class="size-4 motion-safe:animate-spin" />
        </span>
      </.flash>
    </div>
    """
  end
end
