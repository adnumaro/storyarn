defmodule Storyarn.Sheets.Assets.Commands.AssetsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.ObjectStorage, as: Storage
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Assets.Commands.Assets, as: AssetCommands
  alias Storyarn.Sheets.Assets.Entities.AssetRecord

  test "binary uploads use the Sheet-owned pipeline and remain project-scoped" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    binary = File.read!("test/fixtures/images/quadrant_map.png")

    assert {:ok, %AssetRecord{} = asset} =
             Sheets.create_binary_asset(binary, binary_attrs("sheet-audio-art.png"), project, user)

    register_storage_cleanup(asset)

    assert asset.project_id == project.id
    assert asset.uploaded_by_id == user.id
    assert is_binary(asset.blob_hash)
    assert {:ok, ^binary} = Storage.download(asset.key)
    assert Sheets.get_asset(project.id, asset.id).id == asset.id
    assert Sheets.get_asset(other_project.id, asset.id) == nil
  end

  test "committed Sheet asset writes emit the actor product fact" do
    user = user_fixture()
    project = project_fixture(user)
    binary = File.read!("test/fixtures/images/quadrant_map.png")
    test_pid = self()
    tracer = spawn_link(fn -> forward_traces(test_pid) end)

    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Platform, :react_to_event, 4}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Platform, :react_to_event, 4}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, %AssetRecord{} = asset} =
             Sheets.create_binary_asset(binary, binary_attrs("fact.png"), project, user)

    register_storage_cleanup(asset)

    assert_receive {:trace, ^test_pid, :call,
                    {Platform, :react_to_event,
                     [
                       {:user_id, user_id},
                       :sheets,
                       :asset_uploaded,
                       %{project_id: project_id, created_variant: false}
                     ]}}

    assert user_id == user.id
    assert project_id == project.id
  end

  test "unsupported content types are rejected before touching storage" do
    user = user_fixture()
    project = project_fixture(user)

    refute Sheets.allowed_asset_content_type?("application/zip")

    assert {:error, _changeset} =
             Sheets.create_binary_asset(
               "zipbytes",
               %{filename: "bad.zip", content_type: "application/zip"},
               project,
               user
             )
  end

  test "conditional copy failure retains the canonical blob and removes its temporary key" do
    user = user_fixture()
    source_project = project_fixture(user)
    destination_project = project_fixture(user)
    content = "sheet conditional copy"
    hash = sha256(content)
    source_key = blob_key(source_project.id, hash, "png")
    destination_key = blob_key(destination_project.id, hash, "png")

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")
    configure_conditional_copy_remove_failure(:eacces)

    assert {:error, {:conditional_copy_cleanup_required, true, pending_cleanup_key, :eacces}} =
             AssetCommands.create_version_asset_from_storage(
               destination_project.id,
               user.id,
               hash,
               source_key,
               version_metadata("published.png", content)
             )

    on_exit(fn ->
      Storage.delete(source_key)
      Storage.delete(destination_key)
      Storage.delete(pending_cleanup_key)
    end)

    assert {:ok, ^content} = Storage.download(destination_key)
    assert {:error, _reason} = Storage.download(pending_cleanup_key)
    refute File.exists?(storage_path(pending_cleanup_key))

    refute Repo.get_by(AssetRecord,
             project_id: destination_project.id,
             blob_hash: hash
           )
  end

  defp binary_attrs(filename), do: %{filename: filename, content_type: "image/png"}

  defp version_metadata(filename, content) do
    %{
      "filename" => filename,
      "content_type" => "image/png",
      "size" => byte_size(content)
    }
  end

  defp configure_conditional_copy_remove_failure(reason) do
    original_storage = Application.get_env(:storyarn, :storage, [])

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :conditional_copy_file_rm, fn _path -> {:error, reason} end)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)
  end

  defp register_storage_cleanup(asset) do
    extension = asset.content_type |> String.split("/") |> List.last()
    source_key = blob_key(asset.project_id, asset.blob_hash, extension)

    on_exit(fn ->
      Storage.delete(asset.key)
      Storage.delete(source_key)
    end)
  end

  defp blob_key(project_id, hash, "jpeg"), do: "projects/#{project_id}/blobs/#{hash}.jpg"
  defp blob_key(project_id, hash, extension), do: "projects/#{project_id}/blobs/#{hash}.#{extension}"

  defp storage_path(key) do
    upload_dir = :storyarn |> Application.fetch_env!(:storage) |> Keyword.fetch!(:upload_dir)
    Path.join(upload_dir, key)
  end

  defp sha256(binary) do
    :sha256
    |> :crypto.hash(binary)
    |> Base.encode16(case: :lower)
  end

  defp forward_traces(test_pid) do
    receive do
      :stop -> :ok
      message -> send(test_pid, message) && forward_traces(test_pid)
    end
  end
end
