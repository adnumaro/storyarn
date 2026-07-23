defmodule StoryarnWeb.SettingsLive.IntegrationDetailTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.Repo
  alias StoryarnWeb.UserAuth

  @stub StoryarnTest.AI.OpenAI
  @model "personal-deterministic-v1"

  defp with_ai_flag(user) do
    FunWithFlags.enable(:ai_integrations, for_actor: user)
    user
  end

  defp get_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/ProviderIntegrationDetail")
  end

  defp stub_openai(models \\ [@model]) do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"data" => Enum.map(models, &%{"id" => &1})})
    end)
  end

  test "requires the actor feature flag", %{conn: conn} do
    user = user_fixture()

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/integrations/openai")
  end

  test "requires recent authentication for provider configuration", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
    conn = log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/users/settings/integrations/openai")

    assert to ==
             UserAuth.sudo_confirmation_path(~p"/users/settings/integrations/openai")
  end

  test "redirects unknown providers back to the catalog", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    assert {:error, {:live_redirect, %{to: "/users/settings/integrations"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/integrations/not-a-provider")
  end

  test "does not offer a provider without a Storyarn-supported personal model", %{conn: conn} do
    user = with_ai_flag(user_fixture())

    assert {:error, {:live_redirect, %{to: "/users/settings/integrations"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/integrations/deepl")
  end

  test "connects the provider selected by the route, not a client provider field", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stub_openai()

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations/openai")

    render_hook(view, "connect", %{
      "provider" => "anthropic",
      "api_key" => "sk-proj-owner-abcd"
    })

    assert AI.get_active(user, :openai)
    refute AI.get_active(user, :anthropic)

    card = get_vue(view).props["card"]
    assert card["provider"] == "openai"
    assert card["status"] == "connected"
    assert card["key_last_four"] == "abcd"
    assert [%{"model" => @model, "availability" => "available"}] = card["models"]
  end

  test "replaces a key in place after validating it", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stub_openai()
    {:ok, integration} = AI.connect(user, :openai, "sk-proj-owner-abcd")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations/openai")

    render_hook(view, "replace_key", %{"api_key" => "sk-proj-owner-wxyz"})

    refreshed = AI.get_active(user, :openai)
    assert refreshed.id == integration.id
    assert refreshed.key_last_four == "wxyz"
    assert get_vue(view).props["card"]["integration_id"] == integration.id
  end

  test "assigns the route-owned connection and ignores a forged integration id", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)
    other_user = user_fixture()
    stub_openai()

    {:ok, integration} = AI.connect(user, :openai, "sk-proj-owner-abcd")
    {:ok, other_integration} = AI.connect(other_user, :openai, "sk-proj-other-wxyz")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations/openai")

    render_hook(view, "assign_workspace", %{
      "integration_id" => other_integration.id,
      "workspace_id" => workspace.id
    })

    assert Repo.exists?(
             from(assignment in IntegrationWorkspaceAssignment,
               where:
                 assignment.integration_id == ^integration.id and
                   assignment.workspace_id == ^workspace.id and
                   assignment.user_id == ^user.id and is_nil(assignment.revoked_at)
             )
           )

    refute Repo.exists?(
             from(assignment in IntegrationWorkspaceAssignment,
               where:
                 assignment.integration_id == ^other_integration.id and
                   assignment.workspace_id == ^workspace.id and
                   is_nil(assignment.revoked_at)
             )
           )
  end

  test "disconnects without deleting the provider detail destination", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    stub_openai()
    {:ok, _integration} = AI.connect(user, :openai, "sk-proj-owner-abcd")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/integrations/openai")

    render_hook(view, "disconnect", %{})

    refute AI.get_active(user, :openai)
    assert get_vue(view).props["card"]["status"] == "not_connected"
  end
end
