defmodule StoryarnWeb.E2E.SettingsReauthenticationTest do
  @moduledoc """
  Browser coverage for the sudo re-authentication path into account settings.

  Run with: mix test.e2e test/e2e/settings_reauthentication_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @moduletag :e2e

  test "keeps one sudo window after navigating through non-sensitive settings", %{conn: conn} do
    user = user_fixture()
    workspace = Workspaces.get_default_workspace(user)
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
    FunWithFlags.enable(:ai_integrations, for_actor: user)

    conn
    |> authenticate(user, token_authenticated_at: stale_authenticated_at)
    |> visit("/workspaces/#{workspace.slug}")
    |> assert_has("body .phx-connected")
    |> assert_has("#workspace-layout")
    |> evaluate("document.documentElement.dataset.settingsNavigationSentinel = 'kept'")
    |> evaluate(settings_navigation_blank_observer_expression())
    |> evaluate("document.querySelector('#main-content button[aria-pressed]')?.click()")
    |> click("#workspace-user-menu-trigger")
    |> click("#workspace-account-settings-link")
    |> assert_path("/users/confirm-access", query_params: %{return_to: "/users/settings"})
    |> assert_has("#auth-layout-shell")
    |> assert_has("#confirm-password")
    |> evaluate("document.documentElement.dataset.settingsNavigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> evaluate("window.__settingsNavigationBlank", fn value -> assert value == false end)
    |> click("#confirm-access-back-link")
    |> assert_path("/workspaces/#{workspace.slug}")
    |> assert_has("#workspace-layout")
    |> evaluate("document.documentElement.dataset.settingsNavigationSentinel", fn value ->
      assert value == "kept"
    end)
    |> click("#workspace-user-menu-trigger")
    |> click("#workspace-account-settings-link")
    |> assert_path("/users/confirm-access", query_params: %{return_to: "/users/settings"})
    |> fill_in("Password", with: valid_user_password())
    |> click_button("Continue")
    |> assert_path("/users/settings")
    |> assert_has("#settings-layout-wrapper")
    |> assert_has("#profile-display-name")
    |> refute_has("#confirm-access-vue")
    |> evaluate(settings_navigation_blank_observer_expression())
    |> click("a[href='/users/settings/tutorials']")
    |> assert_path("/users/settings/tutorials")
    |> assert_has("[data-testid='restart-all-tutorials']")
    |> refute_has("#confirm-access-vue")
    |> click("a[href='/users/settings/security']")
    |> assert_path("/users/settings/security")
    |> assert_has("#security-password")
    |> refute_has("#confirm-access-vue")
    |> evaluate("window.__settingsNavigationBlank", fn value -> assert value == false end)
    |> click("a[href='/users/settings/tutorials']")
    |> assert_path("/users/settings/tutorials")
    |> assert_has("[data-testid='restart-all-tutorials']")
    |> refute_has("#confirm-access-vue")
    |> click("a[href='/users/settings/integrations']")
    |> assert_path("/users/settings/integrations")
    |> assert_has("#settings-integrations-page")
    |> refute_has("#confirm-access-vue")
    |> click("a[href='/users/settings/ai-team']")
    |> assert_path("/users/settings/ai-team")
    |> assert_has("#settings-ai-team-overview-page")
    |> click("#configure-ai-team-#{workspace.slug}")
    |> assert_path("/users/settings/ai-team/#{workspace.slug}")
    |> assert_has("#settings-ai-team-page")
    |> assert_has("[data-preference-slot='general_assistant']")
    |> assert_has("[data-preference-slot='writing_assistant']")
    |> assert_has("[data-preference-slot='illustrator']")
    |> assert_has("[data-preference-slot='voice']")
    |> refute_has("#ai-team-workspace-selector")
    |> refute_has("#confirm-access-vue")
  end

  test "submits the real password form as POST and rotates the authenticated session", %{conn: conn} do
    user = user_fixture()
    new_password = valid_user_password() <> " changed"
    conn = authenticate(conn, user)
    [old_session] = Repo.all_by(UserToken, user_id: user.id, context: "session")

    conn
    |> visit("/users/settings/security")
    |> assert_has("#security-password")
    |> fill_in("#security-password", "New password", with: new_password)
    |> fill_in("#security-password-confirmation", "Confirm new password", with: new_password)
    |> click_button("Update Password")
    |> assert_has("#flash-info", text: "Password updated successfully!")
    |> assert_path("/users/settings/security")
    |> assert_has("#security-password")

    assert Accounts.get_user_by_email_and_password(user.email, new_password)
    refute Repo.get(UserToken, old_session.id)

    assert [%UserToken{id: new_session_id}] =
             Repo.all_by(UserToken, user_id: user.id, context: "session")

    refute new_session_id == old_session.id
  end

  defp settings_navigation_blank_observer_expression do
    """
    (() => {
      window.__settingsNavigationBlank = false;
      const inspect = () => {
        const surface = document.querySelector(
          '#workspace-layout, #auth-layout-shell, #settings-layout-wrapper'
        );

        if (!surface || (surface.children.length === 0 && surface.textContent.trim() === '')) {
          window.__settingsNavigationBlank = true;
        }
      };

      let pendingFrame;
      const inspectNextFrame = () => {
        if (pendingFrame) cancelAnimationFrame(pendingFrame);
        pendingFrame = requestAnimationFrame(inspect);
      };

      new MutationObserver(inspectNextFrame).observe(document.body, {
        childList: true,
        subtree: true,
      });
      inspect();
    })()
    """
  end
end
