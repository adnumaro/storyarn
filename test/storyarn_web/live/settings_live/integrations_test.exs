defmodule StoryarnWeb.SettingsLive.IntegrationsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias StoryarnWeb.UserAuth

  @stub StoryarnTest.AI.OpenAI

  defp with_ai_flag(user) do
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

  test "requires fresh sudo authentication before exposing credential summaries", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
    conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/users/settings/integrations")

    assert to == UserAuth.sudo_confirmation_path(~p"/users/settings/integrations")
  end

  test "renders a compact read-only provider catalog with detail destinations", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    cards = get_vue(view).props["cards"]
    supported_providers = MapSet.new(AI.model_catalog(), & &1.provider)

    assert MapSet.new(cards, & &1["provider"]) == supported_providers
    refute Enum.any?(cards, &(&1["provider"] == "deepl"))

    openai = Enum.find(cards, &(&1["provider"] == "openai"))
    assert openai["status"] == "not_connected"
    assert openai["detail_path"] == "/users/settings/integrations/openai"
    assert openai["workspace_count"] == 0
    assert is_integer(openai["compatible_model_count"])
    refute Map.has_key?(openai, "workspace_assignments")
    refute Map.has_key?(openai, "models")
  end

  test "summarizes one account connection reused by multiple workspaces", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    scope = user_scope_fixture(user)
    first_workspace = workspace_fixture(user)
    second_workspace = create_additional_workspace!(user)

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => "personal-deterministic-v1"}]})
    end)

    {:ok, integration} = AI.connect(user, :openai, "sk-proj-owner-abcd")
    {:ok, _assignment} = AI.assign_integration(scope, integration.id, first_workspace.id)
    {:ok, _assignment} = AI.assign_integration(scope, integration.id, second_workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations")

    openai =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("cards")
      |> Enum.find(&(&1["provider"] == "openai"))

    assert openai["status"] == "connected"
    assert openai["key_last_four"] == "abcd"
    assert openai["workspace_count"] == 2
    assert openai["compatible_model_count"] == 1
  end

  defp create_additional_workspace!(owner) do
    unique = System.unique_integer([:positive])

    workspace =
      %Workspace{}
      |> Ecto.Changeset.change(%{
        name: "Additional Workspace #{unique}",
        slug: "additional-workspace-#{unique}",
        owner_id: owner.id
      })
      |> Repo.insert!()

    workspace_membership_fixture(workspace, owner, "owner")
    workspace
  end
end
