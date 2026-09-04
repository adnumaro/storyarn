defmodule StoryarnWeb.Components.SettingsLayout do
  @moduledoc """
  LiveVue layout boundary for account, workspace, and project settings pages.

  The route LiveView owns authorization and page data; the rail context comes
  from `StoryarnWeb.Live.Hooks.SettingsNav` as `@settings_nav`. Page titles
  belong to the injected Vue page (`SettingsPage`), not to this wrapper.
  """

  use StoryarnWeb, :html

  alias StoryarnWeb.FeatureFlagHelpers
  alias StoryarnWeb.Live.Shared.OnboardingHelpers

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :socket, :any, required: true, doc: "the LiveView socket (needed for LiveVue)"
  attr :current_scope, :map, required: true, doc: "the current scope"
  attr :current_path, :string, required: true, doc: "current settings path for nav highlighting"

  attr :settings_nav, :map,
    default: nil,
    doc: "rail context built by StoryarnWeb.Live.Hooks.SettingsNav: current workspace/project, switch options"

  attr :sudo_grant, :string, default: nil, doc: "validated grant for sensitive settings links"
  attr :onboarding, :map, default: %{guides: %{}}
  attr :onboarding_guide, :atom, default: nil
  attr :onboarding_autostart, :boolean, default: false

  slot :inner_block, required: true

  def settings(assigns) do
    # Keep serialization in the attribute expressions so HEEx can track the
    # original assign dependencies. Deriving assigns in this function body
    # marks the LiveVue boundary as changed whenever its injected page rerenders;
    # LiveVue then remounts that page and drops input focus and local form state.
    ~H"""
    <div id="settings-layout-wrapper">
      <.vue
        v-component="live/layouts/settings/Layout"
        v-socket={@socket}
        id="settings-layout"
        current-path={@current_path}
        sudo-grant={@sudo_grant}
        settings-nav={@settings_nav}
        onboarding={
          OnboardingHelpers.client_config(
            @onboarding,
            @onboarding_guide,
            @onboarding_autostart
          )
        }
        feature-flags={FeatureFlagHelpers.client_flags(@current_scope)}
      />

      {render_slot(@inner_block)}

      <Layouts.command_palette
        socket={@socket}
        current_scope={@current_scope}
        project_context={project_context?(@settings_nav)}
        sudo_grant={@sudo_grant}
      />
      <Layouts.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  defp project_context?(%{project: %{}}), do: true
  defp project_context?(_settings_nav), do: false
end
