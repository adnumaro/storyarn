defmodule Storyarn.Projects.Assets.Commands.AssetRegistrationTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  test "registration is a silent transaction-bound SQL port with a neutral receipt" do
    user = user_fixture()
    project = project_fixture(user)
    attrs = asset_attrs(project.id, "portrait.png", "portrait")

    assert {:error, :asset_write_transaction_required} =
             Projects.register_uploaded_asset(project.id, user.id, attrs, :generic)

    assert {:ok, receipt} =
             Repo.transact(fn ->
               Projects.register_uploaded_asset(project.id, user.id, attrs, :generic)
             end)

    assert %{asset_id: asset_id, project_id: project_id} = receipt
    assert receipt == %{asset_id: asset_id, project_id: project_id}
    assert project_id == project.id

    assert %Asset{
             id: ^asset_id,
             project_id: ^project_id,
             uploaded_by_id: uploaded_by_id,
             blob_hash: blob_hash
           } = Repo.get(Asset, asset_id)

    assert uploaded_by_id == user.id
    assert blob_hash == attrs.blob_hash
  end

  test "an outer rollback after registration removes the Project-owned asset row" do
    user = user_fixture()
    project = project_fixture(user)
    attrs = asset_attrs(project.id, "rollback.png", "rollback")
    test_pid = self()

    assert {:error, :forced_after_asset_insert} =
             Repo.transaction(fn ->
               assert {:ok, %{asset_id: asset_id}} =
                        Projects.register_materialized_asset(project.id, user.id, attrs)

               send(test_pid, {:registered_before_rollback, asset_id})
               Repo.rollback(:forced_after_asset_insert)
             end)

    assert_receive {:registered_before_rollback, asset_id}
    refute Repo.get(Asset, asset_id)
  end

  test "variant linking updates the owner row and returns only its identity" do
    user = user_fixture()
    project = project_fixture(user)
    original_attrs = asset_attrs(project.id, "original.png", "original")

    assert {:ok, {receipt, variant_id}} =
             Repo.transact(fn ->
               with {:ok, %{asset_id: original_id}} <-
                      Projects.register_uploaded_asset(project.id, user.id, original_attrs, :generic),
                    variant_attrs =
                      asset_attrs(project.id, "variant.webp", "variant", %{
                        "is_variant" => true,
                        "original_asset_id" => original_id
                      }),
                    {:ok, %{asset_id: variant_id}} <-
                      Projects.register_uploaded_asset(project.id, user.id, variant_attrs, :generic),
                    {:ok, receipt} <- Projects.link_asset_variant(project.id, original_id, variant_id) do
                 {:ok, {receipt, variant_id}}
               end
             end)

    assert %{asset_id: original_id, project_id: project_id} = receipt
    assert receipt == %{asset_id: original_id, project_id: project_id}
    assert project_id == project.id
    original = Repo.get!(Asset, original_id)
    assert original.metadata["web_asset_id"] == variant_id
    assert original.metadata["web_url"] == Repo.get!(Asset, variant_id).url
  end

  test "registration rejects invalid ownership and reference inputs without leaving rows behind" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    missing_project_id = 9_999_999_999
    missing_user_id = 9_999_999_999

    assert_registration_error(
      :project_not_found,
      missing_project_id,
      user.id,
      asset_attrs(missing_project_id, "missing-project.png", "missing-project")
    )

    inactive_project = project_fixture(user)

    inactive_project
    |> Project.soft_delete_changeset(%{deleted_at: TimeHelpers.now(), deleted_by_id: user.id})
    |> Repo.update!()

    assert_registration_error(
      :project_not_active,
      inactive_project.id,
      user.id,
      asset_attrs(inactive_project.id, "inactive-project.png", "inactive-project")
    )

    assert_registration_error(
      :user_not_found,
      project.id,
      missing_user_id,
      asset_attrs(project.id, "missing-user.png", "missing-user")
    )

    invalid_key_attrs =
      project.id
      |> asset_attrs("foreign-key.png", "foreign-key")
      |> Map.put(:key, asset_attrs(other_project.id, "foreign-key.png", "foreign-key").key)

    assert_registration_error(:invalid_project_asset_storage_key, project.id, user.id, invalid_key_attrs)

    invalid_hash_attrs =
      project.id
      |> asset_attrs("invalid-hash.png", "invalid-hash")
      |> Map.put(:blob_hash, String.duplicate("A", 64))

    assert_registration_error(:invalid_asset_blob_hash, project.id, user.id, invalid_hash_attrs)

    malformed_family_attrs =
      asset_attrs(project.id, "malformed-family.png", "malformed-family", %{
        "variant_asset_ids" => "not-a-list"
      })

    assert_registration_error(:invalid_asset_family_metadata, project.id, user.id, malformed_family_attrs)

    foreign_asset = register_asset!(other_project, user, "foreign.png", "foreign")

    foreign_family_attrs =
      asset_attrs(project.id, "foreign-family.png", "foreign-family", %{
        "original_asset_id" => foreign_asset.id
      })

    assert_registration_error(
      {:invalid_project_reference, {:asset_family, nil}, foreign_asset.id},
      project.id,
      user.id,
      foreign_family_attrs
    )

    trashed_asset = register_asset!(project, user, "trashed.png", "trashed")

    trashed_asset
    |> Asset.trash_changeset(user.id, "user", TimeHelpers.now())
    |> Repo.update!()

    trashed_family_attrs =
      asset_attrs(project.id, "trashed-family.png", "trashed-family", %{
        "original_asset_id" => trashed_asset.id
      })

    assert_registration_error(
      {:invalid_project_reference, {:asset_family, nil}, trashed_asset.id},
      project.id,
      user.id,
      trashed_family_attrs
    )
  end

  test "registration does not emit platform reactions" do
    user = user_fixture()
    project = project_fixture(user)
    test_pid = self()
    tracer = spawn_link(fn -> forward_traces(test_pid) end)

    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Platform, :react_to_event, 4}, true, [])

    try do
      assert {:ok, %{asset_id: asset_id}} =
               Repo.transact(fn ->
                 Projects.register_uploaded_asset(
                   project.id,
                   user.id,
                   asset_attrs(project.id, "silent.png", "silent"),
                   :generic
                 )
               end)

      assert Repo.get!(Asset, asset_id)
      refute_receive {:trace, ^test_pid, :call, {Platform, :react_to_event, _args}}, 200
    after
      :erlang.trace_pattern({Platform, :react_to_event, 4}, false, [])
      :erlang.trace(test_pid, false, [:call])
      send(tracer, :stop)
    end
  end

  defp assert_registration_error(expected, project_id, user_id, attrs) do
    count_before = Repo.aggregate(from(asset in Asset, where: asset.project_id == ^project_id), :count)

    assert {:error, ^expected} =
             Repo.transact(fn ->
               Projects.register_uploaded_asset(project_id, user_id, attrs, :generic)
             end)

    assert Repo.aggregate(from(asset in Asset, where: asset.project_id == ^project_id), :count) == count_before
  end

  defp register_asset!(project, user, filename, content) do
    assert {:ok, %{asset_id: asset_id}} =
             Repo.transact(fn ->
               Projects.register_uploaded_asset(
                 project.id,
                 user.id,
                 asset_attrs(project.id, filename, content),
                 :generic
               )
             end)

    Repo.get!(Asset, asset_id)
  end

  defp forward_traces(parent) do
    receive do
      :stop ->
        :ok

      message ->
        send(parent, message)
        forward_traces(parent)
    end
  end

  defp asset_attrs(project_id, filename, content, metadata \\ %{}) do
    uuid = Ecto.UUID.generate()

    %{
      filename: filename,
      content_type: if(String.ends_with?(filename, ".webp"), do: "image/webp", else: "image/png"),
      size: byte_size(content),
      key: "projects/#{project_id}/assets/#{uuid}/#{filename}",
      url: "/media/assets/#{uuid}",
      metadata: metadata,
      blob_hash: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
    }
  end
end
