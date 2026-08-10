defmodule Storyarn.References.ProjectReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

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
