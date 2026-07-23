defmodule StoryarnWeb.SettingsLive.IntegrationsTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.Repo
  alias StoryarnWeb.UserAuth

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
    assert anthropic["catalog_status"] == "connection_only"
    assert anthropic["workspace_assignments"] == []
  end

  test "requires fresh sudo authentication before exposing credential settings", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

    conn =
      log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/users/settings/integrations")

    assert to == UserAuth.sudo_confirmation_path(~p"/users/settings/integrations")
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
    assert is_integer(anthropic["integration_id"])
    assert anthropic["catalog_status"] == "connection_only"

    assert [%{"role" => "owner", "state" => "available"}] =
             anthropic["workspace_assignments"]
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
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    {:ok, integration} = AI.connect(user, :anthropic, "sk-ant-api03-good-abcd")
    {:ok, assignment} = AI.assign_integration(scope, integration.id, workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    render_hook(view, "disconnect", %{"provider" => "anthropic"})

    vue = get_vue(view)
    anthropic = Enum.find(vue.props["cards"], &(&1["provider"] == "anthropic"))

    assert anthropic["status"] == "not_connected"
    assert AI.list_active(user) == []
    assert Repo.get!(IntegrationWorkspaceAssignment, assignment.id).revoked_at
  end

  test "owner can enable and disable a connected provider for a workspace", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
    {:ok, integration} = AI.connect(user, :anthropic, "sk-ant-api03-good-abcd")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    render_hook(view, "assign_workspace", %{
      "integration_id" => integration.id,
      "workspace_id" => workspace.id
    })

    card =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("cards")
      |> Enum.find(&(&1["provider"] == "anthropic"))

    assert [%{"assigned" => true, "assignment_id" => assignment_id, "state" => "assigned"}] =
             card["workspace_assignments"]

    assert is_integer(assignment_id)

    render_hook(view, "unassign_workspace", %{
      "integration_id" => integration.id,
      "workspace_id" => workspace.id
    })

    card =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("cards")
      |> Enum.find(&(&1["provider"] == "anthropic"))

    assert [%{"assigned" => false, "assignment_id" => nil, "state" => "available"}] =
             card["workspace_assignments"]
  end

  test "member sees the owner policy block and cannot forge an assignment", %{
    conn: conn
  } do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    member = with_ai_flag(user_fixture())
    workspace_membership_fixture(workspace, member, "member")

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)
    {:ok, integration} = AI.connect(member, :anthropic, "sk-ant-api03-member-abcd")

    assert {:ok, _policy} = AI.update_workspace_policy(owner_scope, workspace.id, [])

    {:ok, view, _html} =
      conn
      |> log_in_user(member)
      |> live(~p"/users/settings/integrations")

    card =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("cards")
      |> Enum.find(&(&1["provider"] == "anthropic"))

    shared = Enum.find(card["workspace_assignments"], &(&1["workspace_id"] == workspace.id))
    assert shared["state"] == "blocked"
    assert shared["can_assign"] == false
    assert shared["reason"] == "member_policy_disabled"

    render_hook(view, "assign_workspace", %{
      "integration_id" => integration.id,
      "workspace_id" => workspace.id
    })

    refute Repo.exists?(
             from(assignment in IntegrationWorkspaceAssignment,
               where:
                 assignment.integration_id == ^integration.id and
                   assignment.workspace_id == ^workspace.id and
                   is_nil(assignment.revoked_at)
             )
           )
  end

  test "cannot assign another user's integration through a forged event", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)
    other_user = user_fixture()

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"data" => []}) end)

    {:ok, other_integration} =
      AI.connect(other_user, :anthropic, "sk-ant-api03-other-wxyz")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    render_hook(view, "assign_workspace", %{
      "integration_id" => other_integration.id,
      "workspace_id" => workspace.id
    })

    refute Repo.exists?(
             from(assignment in IntegrationWorkspaceAssignment,
               where:
                 assignment.integration_id == ^other_integration.id and
                   assignment.workspace_id == ^workspace.id and
                   is_nil(assignment.revoked_at)
             )
           )
  end
end
