defmodule StoryarnWeb.SettingsLive.IntegrationsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures

  alias Storyarn.AI

  @stub StoryarnTest.AI.Anthropic

  defp with_ai_flag(user) do
    # Sandbox rolls back the enable at end of test, so no explicit cleanup.
    FunWithFlags.enable(:ai_integrations, for_actor: user)
    user
  end

  defp get_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsIntegrations")
  end

  test "redirects to settings home when the feature flag is off", %{conn: conn} do
    user = user_fixture()

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/integrations")
  end

  test "renders one card per known provider when the flag is on", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    vue = get_vue(view)
    cards = vue.props["cards"]

    assert length(cards) == length(AI.provider_metadata())

    anthropic = Enum.find(cards, &(&1["provider"] == "anthropic"))
    assert anthropic["status"] == "not_connected"
    assert anthropic["name"] == "Anthropic Claude"
    assert anthropic["key_generation_url"] =~ "platform.claude.com"
  end

  test "connect happy path stores the integration and reflects it in the grid", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    reply = render_hook(view, "connect", %{"provider" => "anthropic", "api_key" => "sk-ant-api03-good-abcd"})

    # render_hook returns the rendered HTML; the reply payload sent to the JS
    # client is asserted indirectly by checking that the LV state changed.
    assert reply

    vue = get_vue(view)
    anthropic = Enum.find(vue.props["cards"], &(&1["provider"] == "anthropic"))

    assert anthropic["status"] == "connected"
    assert anthropic["key_last_four"] == "abcd"
  end

  test "connect surfaces provider rejection without storing the integration", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    render_hook(view, "connect", %{"provider" => "anthropic", "api_key" => "sk-ant-bad"})

    vue = get_vue(view)
    anthropic = Enum.find(vue.props["cards"], &(&1["provider"] == "anthropic"))

    assert anthropic["status"] == "not_connected"
    assert AI.list_active(user) == []
  end

  test "disconnect removes the connected integration", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    {:ok, _} = AI.connect(user, :anthropic, "sk-ant-api03-good-abcd")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    render_hook(view, "disconnect", %{"provider" => "anthropic"})

    vue = get_vue(view)
    anthropic = Enum.find(vue.props["cards"], &(&1["provider"] == "anthropic"))

    assert anthropic["status"] == "not_connected"
    assert AI.list_active(user) == []
  end
end
