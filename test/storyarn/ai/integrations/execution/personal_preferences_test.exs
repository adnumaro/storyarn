defmodule Storyarn.AI.PersonalPreferencesTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.PersonalPreference
  alias Storyarn.AI.PersonalPreferences
  alias Storyarn.AI.Task
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @stub StoryarnTest.AI.OpenAI
  @primary_model "personal-deterministic-v1"
  @alternate_model "personal-alternate-v1"
  @image_model "personal-image-v1"
  @speech_model "personal-speech-v1"

  setup do
    original_catalog = Application.get_env(:storyarn, ModelCatalog, [])

    Application.put_env(
      :storyarn,
      ModelCatalog,
      models: [
        model(@primary_model),
        model(@alternate_model),
        media_model(@image_model, :images, :openai_images, :image),
        media_model(@speech_model, :speech, :openai_speech, :audio)
      ]
    )

    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    FunWithFlags.enable(:ai_integrations, for_actor: owner)

    on_exit(fn ->
      Application.put_env(:storyarn, ModelCatalog, original_catalog)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace}
  end

  test "summary exposes all visible roles and keeps executable versus future media models explicit", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, %{policy_allowed: true, slots: slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    assert Enum.map(slots, & &1.slot) ==
             ~w(general_assistant writing_assistant illustrator voice)

    refute Enum.any?(slots, &(&1.slot == "translator"))
    refute Enum.any?(slots, &(&1.slot == "default"))

    general = Enum.find(slots, &(&1.slot == "general_assistant"))
    writer = Enum.find(slots, &(&1.slot == "writing_assistant"))
    illustrator = Enum.find(slots, &(&1.slot == "illustrator"))
    voice = Enum.find(slots, &(&1.slot == "voice"))

    assert Enum.map(general.options, & &1.model) ==
             [@alternate_model, @primary_model]

    assert Enum.map(writer.options, & &1.model) ==
             [@alternate_model, @primary_model]

    assert Enum.all?(writer.options, &(&1.provider == "openai"))

    assert [%{model: @image_model, implementation_status: "configuration_only"}] =
             illustrator.options

    assert [%{model: @speech_model, implementation_status: "configuration_only"}] =
             voice.options

    assert is_nil(writer.preference)
  end

  test "persists future image and speech choices without marking them executable", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _image} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :illustrator,
               integration.id,
               @image_model
             )

    assert {:ok, _speech} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :voice,
               integration.id,
               @speech_model
             )

    assert {:ok, %{slots: slots}} = AI.personal_preferences(ctx.scope, ctx.workspace.id)

    assert %{status: "configured", implementation_status: "configuration_only"} =
             Enum.find(slots, &(&1.slot == "illustrator")).preference

    assert %{status: "configured", implementation_status: "configuration_only"} =
             Enum.find(slots, &(&1.slot == "voice")).preference

    image_task = struct(Task, capability: :images)
    speech_task = struct(Task, capability: :speech)
    integration_id = integration.id

    assert %{
             status: :configuration_only,
             slot: :illustrator,
             integration_id: ^integration_id,
             model: @image_model
           } =
             PersonalPreferences.resolve(
               ctx.owner.id,
               ctx.workspace.id,
               image_task
             )

    assert %{
             status: :configuration_only,
             slot: :voice,
             integration_id: ^integration_id,
             model: @speech_model
           } =
             PersonalPreferences.resolve(
               ctx.owner.id,
               ctx.workspace.id,
               speech_task
             )
  end

  test "creates and updates one preference per actor workspace slot with audit history", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, created} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               "writing_assistant",
               integration.id,
               @primary_model
             )

    assert created.user_id == ctx.owner.id
    assert created.workspace_id == ctx.workspace.id
    assert created.slot == "writing_assistant"
    assert created.provider == "openai"
    assert created.model == @primary_model

    assert {:ok, updated} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @alternate_model
             )

    assert updated.id == created.id
    assert updated.model == @alternate_model
    assert Repo.aggregate(PersonalPreference, :count) == 1

    assert {:ok, deleted} =
             AI.delete_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant
             )

    assert deleted.id == created.id
    assert Repo.aggregate(PersonalPreference, :count) == 0

    actions =
      AuditEntry
      |> Repo.all()
      |> Enum.map(& &1.action)

    assert "preference_created" in actions
    assert "preference_updated" in actions
    assert "preference_deleted" in actions

    audit = Repo.get_by!(AuditEntry, action: "preference_updated")
    assert audit.actor_id == ctx.owner.id
    assert audit.metadata["preference_id"] == created.id
    assert audit.metadata["workspace_id"] == ctx.workspace.id
    assert audit.metadata["slot"] == "writing_assistant"
    assert audit.metadata["model"] == @alternate_model
  end

  test "returns a changeset instead of raising when an installed slot constraint is stale", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    Repo.query!("""
    ALTER TABLE ai_personal_preferences
    DROP CONSTRAINT ai_personal_preferences_slot_allowed
    """)

    Repo.query!("""
    ALTER TABLE ai_personal_preferences
    ADD CONSTRAINT ai_personal_preferences_slot_allowed
    CHECK (slot IN ('writing_assistant', 'illustrator', 'voice'))
    """)

    assert {:error, %Ecto.Changeset{} = changeset} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :general_assistant,
               integration.id,
               @primary_model
             )

    assert "is invalid" in errors_on(changeset).slot

    refute Repo.get_by(PersonalPreference,
             user_id: ctx.owner.id,
             workspace_id: ctx.workspace.id,
             slot: "general_assistant"
           )
  end

  test "deleting a missing preference returns a domain error", ctx do
    assert {:error, :preference_not_found} =
             AI.delete_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :general_assistant
             )
  end

  test "rejects unassigned, foreign, unavailable, and incompatible routes", ctx do
    integration = connect_openai!(ctx.owner)

    assert {:error, :assignment_required} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:error, :model_unavailable} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               "not-in-the-catalog"
             )

    assert {:error, :capability_mismatch} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :illustrator,
               integration.id,
               @primary_model
             )

    assert {:error, :invalid_preference_slot} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :default,
               integration.id,
               @primary_model
             )

    other = user_fixture()
    other_scope = user_scope_fixture(other)
    workspace_membership_fixture(ctx.workspace, other, "admin")
    FunWithFlags.enable(:ai_integrations, for_actor: other)

    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: other) end)

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["personal_byok"])

    assert {:error, :integration_unavailable} =
             AI.put_personal_preference(
               other_scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )
  end

  test "admin preference writes fail closed when the workspace policy is disabled", ctx do
    member = user_fixture()
    member_scope = user_scope_fixture(member)
    workspace_membership_fixture(ctx.workspace, member, "admin")
    FunWithFlags.enable(:ai_integrations, for_actor: member)

    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: member) end)

    integration = connect_openai!(member, "sk-proj-member-wxyz")

    assert {:error, :member_personal_ai_disabled} =
             AI.assign_integration(member_scope, integration.id, ctx.workspace.id)

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["personal_byok"])

    assert {:ok, _assignment} =
             AI.assign_integration(member_scope, integration.id, ctx.workspace.id)

    assert {:ok, _preference} =
             AI.put_personal_preference(
               member_scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, _policy} = AI.update_workspace_policy(ctx.scope, ctx.workspace.id, [])

    assert {:error, :workspace_policy_disabled} =
             AI.put_personal_preference(
               member_scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, %{policy_allowed: false, slots: slots}} =
             AI.personal_preferences(member_scope, ctx.workspace.id)

    writer = Enum.find(slots, &(&1.slot == "writing_assistant"))
    assert writer.preference.status == "workspace_policy_denied"
    assert writer.options == []
  end

  test "viewer cannot configure personal AI even when the workspace policy allows it", ctx do
    viewer = user_fixture()
    viewer_scope = user_scope_fixture(viewer)
    workspace_membership_fixture(ctx.workspace, viewer, "viewer")
    FunWithFlags.enable(:ai_integrations, for_actor: viewer)

    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: viewer) end)

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["personal_byok"])

    integration = connect_openai!(viewer, "sk-proj-viewer-wxyz")

    assert {:ok, _assignment} =
             AI.assign_integration(viewer_scope, integration.id, ctx.workspace.id)

    assert {:error, :workspace_policy_disabled} =
             AI.put_personal_preference(
               viewer_scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, %{policy_allowed: false, slots: slots}} =
             AI.personal_preferences(viewer_scope, ctx.workspace.id)

    assert Enum.all?(slots, &(&1.options == []))

    assert {:ok, %{workspaces: workspaces}} =
             AI.personal_preferences_overview(viewer_scope)

    overview = Enum.find(workspaces, &(&1.id == ctx.workspace.id))
    refute overview.can_configure
    refute overview.policy_allowed
  end

  test "removing workspace membership permanently invalidates personal AI access", ctx do
    member = user_fixture()
    member_scope = user_scope_fixture(member)
    membership = workspace_membership_fixture(ctx.workspace, member, "admin")
    FunWithFlags.enable(:ai_integrations, for_actor: member)

    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: member) end)

    assert {:ok, _policy} =
             AI.update_workspace_policy(ctx.scope, ctx.workspace.id, ["personal_byok"])

    integration = connect_openai!(member, "sk-proj-membership-wxyz")

    assert {:ok, assignment} =
             AI.assign_integration(member_scope, integration.id, ctx.workspace.id)

    assert {:ok, preference} =
             AI.put_personal_preference(
               member_scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    Repo.delete!(membership)

    refute Repo.get(IntegrationWorkspaceAssignment, assignment.id)
    refute Repo.get(PersonalPreference, preference.id)

    workspace_membership_fixture(ctx.workspace, member, "admin")

    assert {:ok, %{slots: slots}} =
             AI.personal_preferences(member_scope, ctx.workspace.id)

    writer = Enum.find(slots, &(&1.slot == "writing_assistant"))
    assert is_nil(writer.preference)
    assert writer.options == []
  end

  test "the same account connection can select a different primary model per workspace", ctx do
    second_workspace = create_additional_workspace!(ctx.owner)
    integration = connect_openai!(ctx.owner)

    assert {:ok, _assignment} =
             AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _assignment} =
             AI.assign_integration(ctx.scope, integration.id, second_workspace.id)

    assert {:ok, first_preference} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, second_preference} =
             AI.put_personal_preference(
               ctx.scope,
               second_workspace.id,
               :writing_assistant,
               integration.id,
               @alternate_model
             )

    assert first_preference.integration_id == second_preference.integration_id
    refute first_preference.workspace_id == second_preference.workspace_id

    assert {:ok, %{slots: first_slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    assert {:ok, %{slots: second_slots}} =
             AI.personal_preferences(ctx.scope, second_workspace.id)

    assert Enum.find(first_slots, &(&1.slot == "writing_assistant")).preference.model ==
             @primary_model

    assert Enum.find(second_slots, &(&1.slot == "writing_assistant")).preference.model ==
             @alternate_model
  end

  test "overview batches all visible workspaces and preserves repair states without connection ids", ctx do
    integration = connect_openai!(ctx.owner)

    assert {:ok, _assignment} =
             AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _preference} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, _revoked_assignment} =
             AI.unassign_integration(ctx.scope, integration.id, ctx.workspace.id)

    project_owner = user_fixture()
    project_workspace = workspace_fixture(project_owner)
    project = project_fixture(project_owner, %{workspace: project_workspace})
    membership_fixture(project, ctx.owner, "viewer")

    inaccessible_owner = user_fixture()
    inaccessible_workspace = workspace_fixture(inaccessible_owner)

    assert {:ok, %{workspaces: workspaces}} =
             AI.personal_preferences_overview(ctx.scope)

    assert MapSet.new(workspaces, & &1.id) ==
             MapSet.new([ctx.workspace.id, project_workspace.id])

    refute Enum.any?(workspaces, &(&1.id == inaccessible_workspace.id))

    owned = Enum.find(workspaces, &(&1.id == ctx.workspace.id))
    assert owned.role == "owner"
    assert owned.policy_allowed
    assert owned.can_configure

    writer = Enum.find(owned.slots, &(&1.slot == "writing_assistant"))
    assert writer.available
    assert writer.preference.provider == "openai"
    assert writer.preference.model == @primary_model
    assert writer.preference.status == "assignment_required"
    refute Map.has_key?(writer.preference, :integration_id)
    refute Map.has_key?(writer.preference, :id)

    assert Enum.find(owned.slots, &(&1.slot == "illustrator")).available
    assert Enum.find(owned.slots, &(&1.slot == "voice")).available

    project_only = Enum.find(workspaces, &(&1.id == project_workspace.id))

    assert is_nil(project_only.role)
    refute project_only.policy_allowed
    refute project_only.can_configure
    assert Enum.all?(project_only.slots, &is_nil(&1.preference))
  end

  test "overview availability uses only the current catalog version", ctx do
    configured_catalog = Application.get_env(:storyarn, ModelCatalog, [])
    versioned_model = "superseded-model"

    current =
      versioned_model
      |> model()
      |> Map.put(:catalog_version, 2)
      |> Map.put(:deprecated, true)

    Application.put_env(:storyarn, ModelCatalog, models: [model(versioned_model), current])

    on_exit(fn ->
      Application.put_env(:storyarn, ModelCatalog, configured_catalog)
    end)

    assert {:ok, %{workspaces: workspaces}} =
             AI.personal_preferences_overview(ctx.scope)

    owned = Enum.find(workspaces, &(&1.id == ctx.workspace.id))

    refute Enum.find(owned.slots, &(&1.slot == "general_assistant")).available
    refute Enum.find(owned.slots, &(&1.slot == "writing_assistant")).available
  end

  test "project-only access cannot read or mutate workspace AI configuration", ctx do
    project_owner = user_fixture()
    project_owner_scope = user_scope_fixture(project_owner)
    project_workspace = workspace_fixture(project_owner)
    project = project_fixture(project_owner, %{workspace: project_workspace})
    membership_fixture(project, ctx.owner, "editor")

    assert {:ok, _policy} =
             AI.update_workspace_policy(
               project_owner_scope,
               project_workspace.id,
               ["personal_byok"]
             )

    integration = connect_openai!(ctx.owner)

    assert {:error, :workspace_unavailable} =
             AI.assign_integration(ctx.scope, integration.id, project_workspace.id)

    assert {:error, :workspace_unavailable} =
             AI.personal_preferences(ctx.scope, project_workspace.id)

    assert {:error, :workspace_unavailable} =
             AI.put_personal_preference(
               ctx.scope,
               project_workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )
  end

  test "key replacement preserves a primary preference as a repairable state", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, preference} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => @alternate_model}]})
    end)

    assert {:ok, replaced} =
             AI.replace_integration_key(
               ctx.owner,
               integration,
               "sk-proj-replacement-wxyz"
             )

    assert replaced.id == integration.id

    assert {:ok, %{slots: slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    repaired = Enum.find(slots, &(&1.slot == "writing_assistant")).preference
    assert repaired.id == preference.id
    assert repaired.model == @primary_model
    assert repaired.status == "model_unavailable"

    assert {:ok,
            [
              %{
                preference_id: preference_id,
                workspace_id: workspace_id,
                workspace_name: workspace_name,
                workspace_slug: workspace_slug,
                slot: "writing_assistant",
                provider: "openai",
                model: @primary_model,
                status: "model_unavailable"
              }
            ]} = AI.personal_preference_impacts(ctx.scope, integration.id)

    assert preference_id == preference.id
    assert workspace_id == ctx.workspace.id
    assert workspace_name == ctx.workspace.name
    assert workspace_slug == ctx.workspace.slug

    other = user_fixture()
    other_scope = user_scope_fixture(other)
    FunWithFlags.enable(:ai_integrations, for_actor: other)
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: other) end)

    assert {:error, :integration_unavailable} =
             AI.personal_preference_impacts(other_scope, integration.id)

    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 401, "{}") end)
    assert {:error, :invalid_key} = AI.revalidate_integration(ctx.owner, replaced)

    assert {:ok, %{slots: disconnected_slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    disconnected =
      Enum.find(disconnected_slots, &(&1.slot == "writing_assistant")).preference

    assert disconnected.id == preference.id
    assert disconnected.status == "provider_disconnected"
  end

  test "assignment removal and disconnection preserve explicit repair states", ctx do
    integration = connect_openai!(ctx.owner)
    assert {:ok, _assignment} = AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _preference} =
             AI.put_personal_preference(
               ctx.scope,
               ctx.workspace.id,
               :writing_assistant,
               integration.id,
               @primary_model
             )

    assert {:ok, _revoked_assignment} =
             AI.unassign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, %{slots: slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    writer = Enum.find(slots, &(&1.slot == "writing_assistant"))
    assert writer.preference.status == "assignment_required"
    assert writer.preference.provider == "openai"
    assert writer.preference.model == @primary_model

    assert {:ok, _replacement} =
             AI.assign_integration(ctx.scope, integration.id, ctx.workspace.id)

    assert {:ok, _revoked} = AI.revoke(ctx.owner, integration)

    assert {:ok, %{slots: slots}} =
             AI.personal_preferences(ctx.scope, ctx.workspace.id)

    writer = Enum.find(slots, &(&1.slot == "writing_assistant"))
    assert writer.preference.status == "provider_disconnected"
    assert writer.options == []
  end

  test "database guard rejects another actor's integration identity", ctx do
    integration = connect_openai!(ctx.owner)
    other = user_fixture()

    assert_raise Postgrex.Error, ~r/identity does not match/, fn ->
      Repo.transaction(fn ->
        %PersonalPreference{}
        |> PersonalPreference.create_changeset(%{
          user_id: other.id,
          workspace_id: ctx.workspace.id,
          integration_id: integration.id,
          slot: "writing_assistant",
          provider: integration.provider,
          model: @primary_model
        })
        |> Repo.insert!(mode: :savepoint)
      end)
    end
  end

  test "database guard requires an active workspace assignment", ctx do
    integration = connect_openai!(ctx.owner)

    assert_raise Postgrex.Error, ~r/requires an active workspace assignment/, fn ->
      Repo.transaction(fn ->
        %PersonalPreference{}
        |> PersonalPreference.create_changeset(%{
          user_id: ctx.owner.id,
          workspace_id: ctx.workspace.id,
          integration_id: integration.id,
          slot: "writing_assistant",
          provider: integration.provider,
          model: @primary_model
        })
        |> Repo.insert!(mode: :savepoint)
      end)
    end
  end

  defp connect_openai!(user, api_key \\ "sk-proj-owner-abcd") do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "data" => [
          %{"id" => @primary_model},
          %{"id" => @alternate_model},
          %{"id" => @image_model},
          %{"id" => @speech_model}
        ]
      })
    end)

    assert {:ok, integration} = AI.connect(user, :openai, api_key)
    integration
  end

  defp model(name) do
    %{
      provider: "openai",
      model: name,
      catalog_version: 1,
      capabilities: [:translation, :suggestions, :tasks],
      input_modalities: [:text],
      output_modalities: [:text],
      structured_output: :json_schema,
      api_family: :structured_text,
      implementation_status: :executable,
      release_stage: :stable,
      context_window: 128_000,
      max_output_tokens: 8_192,
      processing_locations: ["provider-controlled"],
      pricing_version: nil,
      deprecated: false
    }
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
