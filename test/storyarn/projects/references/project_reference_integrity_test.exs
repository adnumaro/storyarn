defmodule Storyarn.Projects.References.ProjectReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.References.ProjectReferenceIntegrity
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  describe "normalize_optional_id/1" do
    test "normalizes optional positive PostgreSQL bigint IDs" do
      assert {:ok, nil} = ProjectReferenceIntegrity.normalize_optional_id(nil)
      assert {:ok, nil} = ProjectReferenceIntegrity.normalize_optional_id("")
      assert {:ok, 1} = ProjectReferenceIntegrity.normalize_optional_id(1)
      assert {:ok, 1} = ProjectReferenceIntegrity.normalize_optional_id("1")
      assert {:ok, @max_pg_bigint} = ProjectReferenceIntegrity.normalize_optional_id(@max_pg_bigint)
      assert {:ok, @max_pg_bigint} = ProjectReferenceIntegrity.normalize_optional_id(to_string(@max_pg_bigint))
    end

    test "rejects nonpositive, oversized and nonscalar IDs" do
      invalid_ids = [
        0,
        -1,
        "0",
        "-1",
        @max_pg_bigint + 1,
        to_string(@max_pg_bigint + 1),
        "not-an-id",
        1.0,
        [1],
        %{id: 1}
      ]

      for id <- invalid_ids do
        assert :error = ProjectReferenceIntegrity.normalize_optional_id(id)
      end
    end
  end

  test "asset reference validation rejects rows in asset trash" do
    user = user_fixture()
    project = project_fixture(user)
    asset = audio_asset_fixture(project, user)

    {1, _rows} =
      Repo.update_all(
        from(candidate in Asset, where: candidate.id == ^asset.id),
        set: [
          deleted_at: TimeHelpers.now(),
          deleted_by_id: user.id,
          deletion_reason: "user",
          deletion_generation: 1
        ]
      )

    assert {:ok,
            {
              {:error, {:invalid_project_reference, :audio_asset_id, reference_asset_id}},
              {:error, {:invalid_asset_content_type, :audio_asset_id, content_type_asset_id}}
            }} =
             Repo.transaction(fn ->
               {
                 ProjectReferenceIntegrity.lock_active_references(project.id, [
                   {:asset, :audio_asset_id, asset.id}
                 ]),
                 ProjectReferenceIntegrity.ensure_locked_asset_content_type(
                   project.id,
                   asset.id,
                   :audio_asset_id,
                   "audio/%"
                 )
               }
             end)

    assert reference_asset_id == asset.id
    assert content_type_asset_id == asset.id
  end
end
