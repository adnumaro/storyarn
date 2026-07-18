defmodule Storyarn.Versioning.AssetMaterializationScopeTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Versioning.AssetMaterializationScope

  test "rejects an unexpected callback result without leaking owned storage" do
    project = project_fixture(user_fixture())
    storage_key = "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/unexpected-result.bin"

    assert {:ok, _url} =
             Assets.storage_upload(storage_key, "temporary materialization", "application/octet-stream")

    on_exit(fn -> Assets.storage_delete(storage_key) end)

    assert {:error, {:invalid_asset_materialization_scope_result, :ok}} =
             AssetMaterializationScope.run([], fn opts ->
               :ok = StorageCompensation.track(opts[:asset_copy_tracker], storage_key)
               :ok
             end)

    assert {:error, :enoent} = Assets.storage_download(storage_key)
  end
end
