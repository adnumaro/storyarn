defmodule StoryarnWeb.Components.Sidebar do
  @moduledoc """
  Sidebar component for workspace navigation and user menu.
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Phoenix.LiveView.JS

  attr :current_user, :map, required: true
  attr :workspaces, :list, required: true
  attr :current_workspace, :map, default: nil

  def sidebar(assigns) do
    ~H"""
    <aside class="w-64 h-screen bg-base-200 flex flex-col border-r border-base-300">
      <%!-- Logo --%>
      <div class="p-4 border-b border-base-300">
        <.link navigate="/" class="flex items-center gap-2">
          <img src={~p"/images/logo.svg"} alt="Storyarn" class="w-8 h-8" />
          <span class="text-lg font-bold">Storyarn</span>
        </.link>
      </div>

      <%!-- Workspaces list --%>
      <nav class="flex-1 overflow-y-auto p-2">
        <div class="text-xs uppercase text-base-content/50 px-2 py-1 font-semibold tracking-wide">
          {gettext("Workspaces")}
        </div>
        <ul class="menu menu-sm gap-1 p-0">
          <li :for={workspace <- @workspaces}>
            <.link
              navigate={~p"/workspaces/#{workspace.slug}"}
              class={[
                "flex items-center gap-2",
                @current_workspace && @current_workspace.id == workspace.id && "active"
              ]}
            >
              <span
                class="w-2 h-2 rounded-full shrink-0"
                style={"background: #{workspace.color || "#6366f1"}"}
              >
              </span>
              <span class="truncate">{workspace.name}</span>
            </.link>
          </li>
        </ul>
      </nav>

      <%!-- New workspace button --%>
      <div class="p-2 border-t border-base-300">
        <.link navigate={~p"/workspaces/new"} class="btn btn-ghost btn-sm w-full justify-start gap-2">
          <.icon name="plus" class="size-4" />
          {gettext("New workspace")}
        </.link>
      </div>

      <%!-- User footer with dropdown --%>
      <div class="p-2 border-t border-base-300">
        <.user_dropdown current_user={@current_user} />
      </div>
    </aside>
    """
  end

  attr :current_user, :map, required: true

  def user_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-top w-full">
      <div
        tabindex="0"
        role="button"
        class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-300 w-full cursor-pointer"
      >
        <.member_avatar user={@current_user} size={:sm} />
        <span class="text-sm truncate flex-1">
          {@current_user.display_name || @current_user.email}
        </span>
        <.icon name="more-vertical" class="size-4 opacity-50" />
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box w-56 shadow-lg border border-base-300 mb-2 z-50"
      >
        <li>
          <.link navigate={~p"/users/settings"} class="gap-2">
            <.icon name="user" class="size-4" />
            {gettext("Profile")}
          </.link>
        </li>
        <li>
          <.link navigate={~p"/users/settings"} class="gap-2 justify-between">
            <span class="flex items-center gap-2">
              <.icon name="settings" class="size-4" />
              {gettext("Preferences")}
            </span>
            <kbd class="kbd kbd-xs">E</kbd>
          </.link>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="toggle"
            class="gap-2 justify-between"
          >
            <span class="flex items-center gap-2">
              <.icon name="moon" class="size-4 dark:hidden" />
              <.icon name="sun" class="size-4 hidden dark:block" />
              {gettext("Dark mode")}
            </span>
            <kbd class="kbd kbd-xs">D</kbd>
          </button>
        </li>
        <div class="divider my-1"></div>
        <li>
          <.link href={~p"/users/log-out"} method="delete" class="gap-2">
            <.icon name="log-out" class="size-4" />
            {gettext("Log out")}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg]

  def member_avatar(assigns) do
    size_classes = %{
      xs: "w-6 h-6 text-xs",
      sm: "w-8 h-8 text-xs",
      md: "w-10 h-10 text-sm",
      lg: "w-12 h-12 text-base"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    ~H"""
    <div class="avatar placeholder">
      <div class={"bg-neutral text-neutral-content rounded-full #{@size_class}"}>
        <span>{get_initials(@user)}</span>
      </div>
    </div>
    """
  end

  defp get_initials(user) do
    name = user.display_name || user.email || ""

    name
    |> String.split(~r/[\s@]/, parts: 2)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end
end
