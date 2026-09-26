defmodule StoryarnWeb.SettingsLive.PlanBilling do
  @moduledoc """
  Account settings › Plan & billing: the plan the account is on, the editor
  seats it uses and the workspaces it owns. The plan belongs to the person,
  and every workspace they own takes its limits from it.

  These are totals across the whole account, so the page only ever shows the
  signed-in user's own account. Read-only until payments exist; plan changes
  go through the contact page.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Commercial

  @impl true
  def mount(_params, _session, socket) do
    usage = Commercial.account_usage(socket.assigns.current_scope.user.id)

    {:ok,
     socket
     |> assign(:page_title, dgettext("settings", "Plan & billing"))
     |> assign(:current_path, ~p"/users/settings/plan")
     |> assign(:account, serialize_account(usage))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/account/settings/AccountSettingsPlanBilling"
        v-socket={@socket}
        v-inject="settings-layout"
        id="settings-plan-billing"
        account={@account}
        contact-path={~p"/contact"}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp serialize_account(usage) do
    %{
      plan: %{key: usage.plan.key, name: usage.plan.name},
      seats: %{used: usage.seats.used, limit: serialize_limit(usage.seats.limit)},
      workspaces: %{used: usage.workspaces.used, limit: serialize_limit(usage.workspaces.limit)}
    }
  end

  defp serialize_limit(:unlimited), do: "unlimited"
  defp serialize_limit(:paid_seats), do: "paid_seats"
  defp serialize_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp serialize_limit(_unknown_limit), do: nil
end
