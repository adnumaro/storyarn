defmodule StoryarnWeb.ProjectLive.Components.SettingsSidebar do
  @moduledoc """
  Shared settings sidebar component used by project settings and export/import pages.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :active, :atom, required: true

  def settings_sidebar(assigns) do
    assigns = assign(assigns, :nav, build_nav(assigns))

    ~H"""
    <div class="fixed left-3 top-[76px] bottom-3 z-[1010] w-60 flex flex-col surface-panel overflow-hidden">
      <div class="px-2 pt-2 pb-2 border-b border-base-300">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-base-content/70 hover:bg-base-content/5"
        >
          <.icon name="chevron-left" class="size-4" />
          {dgettext("projects", "Back to project")}
        </.link>
      </div>

      <nav class="flex-1 overflow-y-auto p-2 space-y-5">
        <div :for={section <- @nav}>
          <h3 class="text-xs font-semibold uppercase text-base-content/50 px-2 mb-2">
            {section.title}
          </h3>
          <ul class="space-y-0.5">
            <li :for={item <- section.items}>
              <.link
                navigate={item.path}
                class={[
                  "flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm",
                  @active == item.key && "bg-base-content/5 font-medium",
                  @active != item.key && "hover:bg-base-content/5"
                ]}
              >
                <.icon name={item.icon} class="size-4" />
                {item.label}
              </.link>
            </li>
          </ul>
        </div>
      </nav>
    </div>
    """
  end

  defp build_nav(assigns) do
    base = ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/settings"

    [
      %{
        title: dgettext("projects", "General"),
        items: [
          %{
            label: dgettext("projects", "General"),
            path: base,
            icon: "settings",
            key: :general
          }
        ]
      },
      %{
        title: dgettext("projects", "Integrations"),
        items: [
          %{
            label: dgettext("projects", "Localization"),
            path: "#{base}/localization",
            icon: "languages",
            key: :localization
          }
        ]
      },
      %{
        title: dgettext("projects", "Administration"),
        items: [
          %{
            label: dgettext("projects", "Members"),
            path: "#{base}/members",
            icon: "users",
            key: :members
          },
          %{
            label: dgettext("projects", "Import & Export"),
            path: "#{base}/export-import",
            icon: "package",
            key: :export_import
          }
        ]
      }
    ]
  end
end
