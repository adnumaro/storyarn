defmodule StoryarnWeb.Components.SettingsLayout do
  @moduledoc """
  Settings layout component with Linear-style sidebar navigation.
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents

  @doc """
  Renders the settings layout with sidebar navigation.

  ## Examples

      <.settings_layout current_path={@current_path} current_scope={@current_scope}>
        <:title>Profile</:title>
        <:subtitle>Manage your personal information</:subtitle>
        <p>Content here</p>
      </.settings_layout>
  """
  attr :current_path, :string, required: true
  attr :current_scope, :map, required: true

  slot :title, required: true
  slot :subtitle
  slot :inner_block, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="flex min-h-[calc(100vh-4rem)]">
      <%!-- Settings sidebar --%>
      <aside class="w-64 border-r border-base-300 p-4 hidden lg:block">
        <%!-- Back to app --%>
        <.link
          navigate={~p"/workspaces"}
          class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content mb-6"
        >
          <.icon name="hero-chevron-left" class="size-4" />
          {gettext("Back to app")}
        </.link>

        <%!-- Navigation sections --%>
        <nav class="space-y-6">
          <div :for={section <- settings_sections(@current_scope)}>
            <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
              {section.label}
            </h3>
            <ul class="space-y-1">
              <li :for={item <- section.items}>
                <.link
                  navigate={item.path}
                  class={[
                    "flex items-center gap-2 px-2 py-1.5 rounded text-sm",
                    @current_path == item.path && "bg-primary/10 text-primary",
                    @current_path != item.path && "hover:bg-base-200"
                  ]}
                >
                  <.icon name={item.icon} class="size-4" />
                  {item.label}
                  <kbd :if={item[:shortcut]} class="kbd kbd-xs ml-auto">{item.shortcut}</kbd>
                </.link>
              </li>
            </ul>
          </div>
        </nav>
      </aside>

      <%!-- Settings content --%>
      <main class="flex-1 p-8 max-w-3xl">
        <%!-- Mobile back link --%>
        <.link
          navigate={~p"/workspaces"}
          class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content mb-6 lg:hidden"
        >
          <.icon name="hero-chevron-left" class="size-4" />
          {gettext("Back to app")}
        </.link>

        <.header>
          {render_slot(@title)}
          <:subtitle :if={@subtitle != []}>
            {render_slot(@subtitle)}
          </:subtitle>
        </.header>

        <div class="mt-8">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    """
  end

  defp settings_sections(_current_scope) do
    [
      %{
        label: gettext("Account"),
        items: [
          %{
            label: gettext("Profile"),
            path: ~p"/users/settings",
            icon: "hero-user"
          },
          %{
            label: gettext("Security"),
            path: ~p"/users/settings/security",
            icon: "hero-shield-check"
          },
          %{
            label: gettext("Connected accounts"),
            path: ~p"/users/settings/connections",
            icon: "hero-link"
          }
        ]
      }
    ]
    # Workspace settings section can be added later when routes are implemented
  end
end
