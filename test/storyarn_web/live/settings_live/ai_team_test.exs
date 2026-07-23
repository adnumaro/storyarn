defmodule StoryarnWeb.SettingsLive.AITeamTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.PersonalPreference
  alias Storyarn.Repo
  alias StoryarnWeb.UserAuth

  @stub StoryarnTest.AI.OpenAI
  @model "personal-deterministic-v1"
  @image_model "personal-image-v1"
  @speech_model "personal-speech-v1"

  setup do
    original_catalog = Application.fetch_env(:storyarn, ModelCatalog)
    configured_models = Application.fetch_env!(:storyarn, ModelCatalog)[:models]

    Application.put_env(:storyarn, ModelCatalog,
      models:
        configured_models ++
          [
            media_model(@image_model, :images, :openai_images, :image),
            media_model(@speech_model, :speech, :openai_speech, :audio)
          ]
    )

    on_exit(fn -> restore_env(ModelCatalog, original_catalog) end)
    :ok
  end

  defp with_ai_flag(user) do
    FunWithFlags.enable(:ai_integrations, for_actor: user)
    user
  end

  defp get_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/MyAITeam")
  end

  defp get_overview_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/MyAITeamOverview")
  end

  test "redirects when the actor-targeted AI flag is disabled", %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/ai-team")
  end

  test "requires recent authentication for the personal routing screen", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)
    stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)

    conn =
      log_in_user(conn, user, token_authenticated_at: stale_authenticated_at)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/users/settings/ai-team/#{workspace.slug}")

    assert to ==
             UserAuth.sudo_confirmation_path(~p"/users/settings/ai-team/#{workspace.slug}")

    assert {:error, {:live_redirect, %{to: overview_to}}} =
             live(conn, ~p"/users/settings/ai-team")

    assert overview_to ==
             UserAuth.sudo_confirmation_path(~p"/users/settings/ai-team")
  end

  test "renders the visible personal roles without Translator or DeepL", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    integration = connect_openai!(user)
    assert {:ok, _assignment} = AI.assign_integration(scope, integration.id, workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    props = get_vue(view).props

    assert props["workspace"]["id"] == workspace.id
    assert props["providers-path"] == "/users/settings/integrations"
    assert props["overview-path"] == "/users/settings/ai-team"

    slots = props["slots"]

    assert Enum.map(slots, & &1["slot"]) ==
             ~w(general_assistant writing_assistant illustrator voice)

    refute Enum.any?(slots, &(&1["slot"] == "translator"))

    general = Enum.find(slots, &(&1["slot"] == "general_assistant"))
    assert [%{"provider" => "openai", "model" => @model}] = general["options"]

    writer = Enum.find(slots, &(&1["slot"] == "writing_assistant"))
    assert [%{"provider" => "openai", "model" => @model}] = writer["options"]
    refute Enum.any?(writer["options"], &(&1["provider"] == "deepl"))

    assert [
             %{
               "provider" => "openai",
               "model" => @image_model,
               "implementation_status" => "configuration_only"
             }
           ] = Enum.find(slots, &(&1["slot"] == "illustrator"))["options"]

    assert [
             %{
               "provider" => "openai",
               "model" => @speech_model,
               "implementation_status" => "configuration_only"
             }
           ] = Enum.find(slots, &(&1["slot"] == "voice"))["options"]
  end

  test "saves and removes a workspace-scoped role preference", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    integration = connect_openai!(user)
    assert {:ok, _assignment} = AI.assign_integration(scope, integration.id, workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    render_hook(view, "save_preference", %{
      "slot" => "writing_assistant",
      "integration_id" => integration.id,
      "model" => @model
    })

    preference =
      Repo.get_by!(PersonalPreference,
        user_id: user.id,
        workspace_id: workspace.id,
        slot: "writing_assistant"
      )

    assert preference.integration_id == integration.id
    assert preference.model == @model

    writer =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("slots")
      |> Enum.find(&(&1["slot"] == "writing_assistant"))

    assert writer["preference"]["status"] == "ready"
    assert writer["preference"]["provider"] == "openai"

    render_hook(view, "delete_preference", %{"slot" => "writing_assistant"})

    refute Repo.get(PersonalPreference, preference.id)

    writer =
      view
      |> get_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("slots")
      |> Enum.find(&(&1["slot"] == "writing_assistant"))

    assert is_nil(writer["preference"])
  end

  test "a stale database slot constraint returns an error without terminating the LiveView", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    integration = connect_openai!(user)
    assert {:ok, _assignment} = AI.assign_integration(scope, integration.id, workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    Repo.query!("""
    ALTER TABLE ai_personal_preferences
    DROP CONSTRAINT ai_personal_preferences_slot_allowed
    """)

    Repo.query!("""
    ALTER TABLE ai_personal_preferences
    ADD CONSTRAINT ai_personal_preferences_slot_allowed
    CHECK (slot IN ('writing_assistant', 'illustrator', 'voice'))
    """)

    render_hook(view, "save_preference", %{
      "slot" => "general_assistant",
      "integration_id" => integration.id,
      "model" => @model
    })

    assert_reply(view, %{status: "error", error: "invalid_data"})
    assert render(view)

    refute Repo.get_by(PersonalPreference,
             user_id: user.id,
             workspace_id: workspace.id,
             slot: "general_assistant"
           )
  end

  test "the workspace in the URL is authoritative over forged event payloads", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    other_owner = with_ai_flag(user_fixture())
    other_owner_scope = user_scope_fixture(other_owner)
    other_workspace = workspace_fixture(other_owner)
    workspace_membership_fixture(other_workspace, user, "member")
    integration = connect_openai!(user)

    assert {:ok, _policy} =
             AI.update_workspace_policy(
               other_owner_scope,
               other_workspace.id,
               ["personal_byok"]
             )

    assert {:ok, _assignment} =
             AI.assign_integration(scope, integration.id, workspace.id)

    assert {:ok, _assignment} =
             AI.assign_integration(scope, integration.id, other_workspace.id)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    render_hook(view, "save_preference", %{
      "workspace_id" => other_workspace.id,
      "slot" => "general_assistant",
      "integration_id" => integration.id,
      "model" => @model
    })

    assert Repo.get_by!(PersonalPreference,
             user_id: user.id,
             workspace_id: workspace.id,
             slot: "general_assistant"
           )

    refute Repo.get_by(PersonalPreference,
             user_id: user.id,
             workspace_id: other_workspace.id,
             slot: "general_assistant"
           )
  end

  test "forged events cannot select another actor's connection", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)
    other = user_fixture()
    other_integration = connect_openai!(other, "sk-proj-other-wxyz")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team/#{workspace.slug}")

    render_hook(view, "save_preference", %{
      "slot" => "writing_assistant",
      "integration_id" => other_integration.id,
      "model" => @model
    })

    refute Repo.get_by(PersonalPreference,
             user_id: user.id,
             workspace_id: workspace.id
           )
  end

  test "overview lists workspace and project-only access with server-owned edit paths", %{
    conn: conn
  } do
    user = with_ai_flag(user_fixture())
    workspace = workspace_fixture(user)

    project_owner = user_fixture()
    project_workspace = workspace_fixture(project_owner)
    project = project_fixture(project_owner, %{workspace: project_workspace})
    membership_fixture(project, user, "viewer")

    inaccessible_owner = user_fixture()
    inaccessible_workspace = workspace_fixture(inaccessible_owner)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/ai-team")

    props = get_overview_vue(view).props
    workspaces = props["workspaces"]

    assert MapSet.new(workspaces, & &1["id"]) ==
             MapSet.new([workspace.id, project_workspace.id])

    refute Enum.any?(
             workspaces,
             &(&1["id"] == inaccessible_workspace.id)
           )

    owned = Enum.find(workspaces, &(&1["id"] == workspace.id))
    assert owned["role"] == "owner"
    assert owned["can_configure"]
    assert owned["edit_path"] == "/users/settings/ai-team/#{workspace.slug}"

    project_only = Enum.find(workspaces, &(&1["id"] == project_workspace.id))

    assert is_nil(project_only["role"])
    refute project_only["policy_allowed"]
    refute project_only["can_configure"]
    assert is_nil(project_only["edit_path"])

    writer =
      Enum.find(project_only["slots"], &(&1["slot"] == "writing_assistant"))

    assert writer["available"]
    assert Enum.find(project_only["slots"], &(&1["slot"] == "voice"))["available"]
  end

  test "editor route rejects project-only workspace access", %{conn: conn} do
    user = with_ai_flag(user_fixture())
    project_owner = user_fixture()
    project_workspace = workspace_fixture(project_owner)
    project = project_fixture(project_owner, %{workspace: project_workspace})
    membership_fixture(project, user, "editor")

    assert {:error, {:live_redirect, %{to: "/users/settings/ai-team"}}} =
             conn
             |> log_in_user(user)
             |> live(~p"/users/settings/ai-team/#{project_workspace.slug}")
  end

  defp connect_openai!(user, api_key \\ "sk-proj-owner-abcd") do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "data" => [
          %{"id" => @model},
          %{"id" => @image_model},
          %{"id" => @speech_model}
        ]
      })
    end)

    assert {:ok, integration} = AI.connect(user, :openai, api_key)
    integration
  end

  defp media_model(name, capability, api_family, output_modality) do
    %{
      provider: "openai",
      model: name,
      catalog_version: 1,
      capabilities: [capability],
      input_modalities: [:text],
      output_modalities: [output_modality],
      structured_output: :none,
      api_family: api_family,
      implementation_status: :configuration_only,
      release_stage: :stable,
      context_window: nil,
      max_output_tokens: nil,
      processing_locations: ["provider-controlled"],
      pricing_version: nil,
      deprecated: false
    }
  end

  defp restore_env(module, {:ok, config}), do: Application.put_env(:storyarn, module, config)
  defp restore_env(module, :error), do: Application.delete_env(:storyarn, module)
end
