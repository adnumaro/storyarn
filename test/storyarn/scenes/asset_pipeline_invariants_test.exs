defmodule Storyarn.Scenes.AssetPipelineInvariantsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.AssetCommands
  alias Storyarn.Scenes.ImageProcessor
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Scenes.Persistence.ProjectRecord
  alias Storyarn.SnapshotReadSwitchStorage

  test "Scene background upload owns dimensions, purpose scheduling and variant linking" do
    user = user_fixture()
    project = project_fixture(user)
    image_path = "test/fixtures/images/quadrant_map.png"

    assert ImageProcessor.available?()

    entry = %{
      client_name: "Scene Background.PNG",
      client_type: "image/png",
      height: 1,
      width: 1
    }

    assert {:ok, %AssetRecord{} = original} =
             AssetCommands.upload_asset(
               image_path,
               entry,
               project,
               user,
               purpose: :scene_background
             )

    assert original.metadata["width"] == 400
    assert original.metadata["height"] == 200

    {linked_original, variant} = await_background_variant(original.id)

    register_storage_cleanup(linked_original)
    register_storage_cleanup(variant)

    assert variant.project_id == project.id
    assert variant.uploaded_by_id == user.id
    assert variant.content_type == "image/webp"
    assert variant.metadata["is_variant"] == true
    assert variant.metadata["original_asset_id"] == original.id
    assert linked_original.metadata["web_asset_id"] == variant.id
    assert linked_original.metadata["web_url"] == variant.url
  end

  test "committed Scene asset writes emit actor and system product facts" do
    user = user_fixture()
    project = project_fixture(user)
    content = "scene analytics payload"
    test_pid = self()
    tracer = spawn_link(fn -> forward_traces(test_pid) end)

    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Platform, :react_to_event, 4}, true, [])

    # The per-process trace flag dies with the test process; only the global
    # trace pattern and the tracer need explicit cleanup here.
    on_exit(fn ->
      :erlang.trace_pattern({Platform, :react_to_event, 4}, false, [])
      send(tracer, :stop)
    end)

    assert {:ok, %AssetRecord{} = user_asset} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "actor.png", content_type: "image/png"},
               project,
               user
             )

    assert_receive {:trace, ^test_pid, :call,
                    {Platform, :react_to_event,
                     [
                       {:user_id, user_id},
                       :scenes,
                       :asset_uploaded,
                       %{project_id: project_id, created_variant: false}
                     ]}}

    assert user_id == user.id
    assert project_id == project.id

    assert {:ok, %AssetRecord{} = system_asset} =
             AssetCommands.create_generated_asset(
               content <> " system",
               %{filename: "system.png", content_type: "image/png"},
               project,
               nil
             )

    assert_receive {:trace, ^test_pid, :call,
                    {Platform, :react_to_event,
                     [
                       :system,
                       :scenes,
                       :asset_uploaded,
                       %{project_id: ^project_id, created_variant: false}
                     ]}}

    register_storage_cleanup(user_asset)
    register_storage_cleanup(system_asset)
  end

  test "repairs a corrupt pre-existing canonical blob before adopting it" do
    user = user_fixture()
    project = project_fixture(user)
    content = "scene canonical payload"
    corrupt = String.duplicate("x", byte_size(content))
    hash = sha256(content)
    canonical_key = blob_key(project.id, hash, "png")

    assert {:ok, _url, true} =
             Storage.put_if_absent(canonical_key, corrupt, "image/png")

    on_exit(fn -> Storage.adapter().delete(canonical_key) end)

    assert {:ok, %AssetRecord{} = asset} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "repaired.png", content_type: "image/png"},
               project,
               user
             )

    on_exit(fn -> Storage.delete(asset.key) end)

    assert asset.blob_hash == hash
    assert {:ok, ^content} = Storage.download(canonical_key)
    assert {:ok, ^content} = Storage.download(asset.key)
  end

  test "fresh raw upload avoids canonical readback while an existing blob is verified" do
    user = user_fixture()
    project = project_fixture(user)
    content = "instrumented scene upload"
    hash = sha256(content)
    canonical_key = blob_key(project.id, hash, "png")
    test_pid = self()

    configure_read_switch_storage()

    SnapshotReadSwitchStorage.observe_io(fn operation, key ->
      send(test_pid, {:scene_storage_io, operation, key})
    end)

    on_exit(fn -> Storage.adapter().delete(canonical_key) end)

    assert {:ok, %AssetRecord{} = first_asset} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "first.png", content_type: "image/png"},
               project,
               user
             )

    assert_receive {:scene_storage_io, :put_if_absent, ^canonical_key}
    refute_receive {:scene_storage_io, :stat, ^canonical_key}, 50
    assert SnapshotReadSwitchStorage.stream_count(canonical_key) == 0

    SnapshotReadSwitchStorage.reset_counts()
    flush_scene_storage_io()

    assert {:ok, %AssetRecord{} = second_asset} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "second.png", content_type: "image/png"},
               project,
               user
             )

    assert_receive {:scene_storage_io, :stat, ^canonical_key}
    assert_receive {:scene_storage_io, :stream_chunk, ^canonical_key}
    assert SnapshotReadSwitchStorage.stream_count(canonical_key) == 1

    on_exit(fn ->
      Storage.delete(first_asset.key)
      Storage.delete(second_asset.key)
    end)
  end

  test "failed repair of an existing MIME-corrupt blob hands off to durable reconciliation" do
    user = user_fixture()
    project = project_fixture(user)
    content = "valid bytes with corrupt provider metadata"
    hash = sha256(content)
    canonical_key = blob_key(project.id, hash, "png")

    configure_read_switch_storage()

    assert {:ok, _url, true} =
             Storage.put_if_absent(canonical_key, content, "image/png")

    SnapshotReadSwitchStorage.override_content_type(canonical_key, "application/pdf")
    SnapshotReadSwitchStorage.set_delete_if_matches_result({:error, :eacces})

    on_exit(fn -> Storage.adapter().delete(canonical_key) end)

    assert {:error, :eacces} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "mime-repair.png", content_type: "image/png"},
               project,
               user
             )

    request =
      StorageCleanupRequest
      |> Repo.all()
      |> Enum.find(fn request ->
        Enum.any?(request.storage_keys, &String.ends_with?(&1, canonical_key))
      end)

    assert %StorageCleanupRequest{} = request
    assert [cleanup_target] = request.storage_keys
    assert String.starts_with?(cleanup_target, "__storyarn_force_delete__:")
    assert {:ok, ^content} = Storage.download(canonical_key)

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(1)
    refute Repo.get(StorageCleanupRequest, request.id)
    # Durable force cleanup deletes only hash-invalid bytes; a canonical blob
    # whose content still matches its hash is retained as repaired.
    assert {:ok, ^content} = Storage.download(canonical_key)
  end

  test "an ambiguous blob write error cannot delete a pre-existing canonical project blob" do
    user = user_fixture()
    project = project_fixture(user)
    content = "pre-existing canonical recovery content"
    hash = sha256(content)
    canonical_key = blob_key(project.id, hash, "png")

    configure_read_switch_storage()

    assert {:ok, _url, true} =
             Storage.put_if_absent(canonical_key, content, "image/png")

    SnapshotReadSwitchStorage.set_put_if_absent_result({:error, :timeout})

    on_exit(fn -> Storage.adapter().delete(canonical_key) end)

    assert {:error, :timeout} =
             AssetCommands.create_generated_asset(
               content,
               %{filename: "ambiguous.png", content_type: "image/png"},
               project,
               user
             )

    request =
      StorageCleanupRequest
      |> Repo.all()
      |> Enum.find(fn request -> request.storage_keys == [canonical_key] end)

    assert %StorageCleanupRequest{} = request
    assert {:ok, ^content} = Storage.download(canonical_key)

    SnapshotReadSwitchStorage.set_put_if_absent_result(:delegate)

    assert :ok = StorageCompensation.retry_persisted_cleanup_requests(1)
    refute Repo.get(StorageCleanupRequest, request.id)
    assert {:ok, ^content} = Storage.download(canonical_key)
  end

  test "sanitized SVG upload never persists the unsanitized input hash" do
    user = user_fixture()
    project = project_fixture(user)

    unsafe_svg =
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert(document.domain)</script><circle r="3"/></svg>|

    unsafe_key = blob_key(project.id, sha256(unsafe_svg), "svg")

    assert {:ok, %AssetRecord{} = asset} =
             AssetCommands.create_sanitized_svg_asset(
               unsafe_svg,
               %{filename: "scene.svg", content_type: "image/svg+xml"},
               project,
               user
             )

    sanitized_key = blob_key(project.id, asset.blob_hash, "svg")

    on_exit(fn ->
      Storage.delete(asset.key)
      Storage.adapter().delete(sanitized_key)
      Storage.adapter().delete(unsafe_key)
    end)

    refute asset.blob_hash == sha256(unsafe_svg)
    assert {:error, :enoent} = Storage.download(unsafe_key)
    assert {:ok, stored_svg} = Storage.download(sanitized_key)
    refute stored_svg =~ "<script"
  end

  test "conditional copy failure retains a newly published canonical blob and drops its temporary key" do
    user = user_fixture()
    source_project = project_fixture(user)
    destination_project = project_fixture(user)
    content = "scene conditional copy"
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
      Storage.adapter().delete(source_key)
      Storage.adapter().delete(destination_key)
      Storage.adapter().delete(pending_cleanup_key)
    end)

    # A content-addressed blob under a committed project is an immutable cache:
    # rollback retains it, and only the temporary copy key becomes unreachable.
    assert {:ok, ^content} = Storage.download(destination_key)
    assert {:error, _reason} = Storage.download(pending_cleanup_key)

    refute Repo.exists?(
             from(asset in AssetRecord,
               where:
                 asset.project_id == ^destination_project.id and
                   asset.blob_hash == ^hash
             )
           )
  end

  test "conditional copy failure preserves a pre-existing blob while removing its temporary key" do
    user = user_fixture()
    source_project = project_fixture(user)
    destination_project = project_fixture(user)
    content = "pre-existing scene blob"
    hash = sha256(content)
    source_key = blob_key(source_project.id, hash, "png")
    destination_key = blob_key(destination_project.id, hash, "png")

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")
    assert {:ok, _url, true} = Storage.put_if_absent(destination_key, content, "image/png")
    configure_conditional_copy_remove_failure(:ebusy)

    assert {:error, {:conditional_copy_cleanup_required, false, pending_cleanup_key, :ebusy}} =
             AssetCommands.create_version_asset_from_storage(
               destination_project.id,
               user.id,
               hash,
               source_key,
               version_metadata("existing.png", content)
             )

    on_exit(fn ->
      Storage.adapter().delete(source_key)
      Storage.adapter().delete(destination_key)
      Storage.adapter().delete(pending_cleanup_key)
    end)

    assert {:ok, ^content} = Storage.download(destination_key)
    assert {:error, _reason} = Storage.download(pending_cleanup_key)
  end

  test "version materialization reports quota exhaustion as a stable two-tuple" do
    user = user_fixture()
    project = project_fixture(user)
    source_project = project_fixture(user)
    content = "cannot fit"
    hash = sha256(content)
    source_key = blob_key(source_project.id, hash, "png")
    destination_key = blob_key(project.id, hash, "png")
    limit = Platform.entitlement_limit(project.workspace_id, :storage_bytes_per_workspace)

    Repo.insert!(%AssetRecord{
      project_id: project.id,
      filename: "full.pdf",
      content_type: "application/pdf",
      size: limit,
      key: asset_key(project.id, "full.pdf"),
      blob_hash: String.duplicate("a", 64),
      metadata: %{}
    })

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")

    on_exit(fn ->
      Storage.adapter().delete(source_key)
      Storage.adapter().delete(destination_key)
    end)

    assert {:error, {:limit_reached, details}} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               user.id,
               hash,
               source_key,
               version_metadata("restored.png", content)
             )

    assert details.required == byte_size(content)
    assert details.available == 0
    assert {:error, :enoent} = Storage.download(destination_key)
  end

  test "version materialization rejects a deleted project before copying storage" do
    user = user_fixture()
    project = project_fixture(user)
    source_project = project_fixture(user)
    content = "deleted project payload"
    hash = sha256(content)
    source_key = blob_key(source_project.id, hash, "png")
    destination_key = blob_key(project.id, hash, "png")

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")

    Repo.update_all(
      from(stored_project in ProjectRecord, where: stored_project.id == ^project.id),
      set: [deleted_at: TimeHelpers.now()]
    )

    on_exit(fn ->
      Storage.adapter().delete(source_key)
      Storage.adapter().delete(destination_key)
    end)

    assert {:error, :project_not_active} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               user.id,
               hash,
               source_key,
               version_metadata("deleted.png", content)
             )

    assert {:error, :enoent} = Storage.download(destination_key)
  end

  test "version materialization rejects an unknown scalar actor before storage adoption" do
    user = user_fixture()
    project = project_fixture(user)
    source_project = project_fixture(user)
    content = "unknown actor payload"
    hash = sha256(content)
    source_key = blob_key(source_project.id, hash, "png")
    destination_key = blob_key(project.id, hash, "png")
    unknown_user_id = 9_223_372_036_854_775_000

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")

    on_exit(fn ->
      Storage.adapter().delete(source_key)
      Storage.adapter().delete(destination_key)
    end)

    assert {:error, :user_not_found} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               unknown_user_id,
               hash,
               source_key,
               version_metadata("unknown.png", content)
             )

    assert {:error, :enoent} = Storage.download(destination_key)
  end

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

  defp configure_read_switch_storage do
    original_storage = Application.get_env(:storyarn, :storage, [])

    start_supervised!(%{
      id: SnapshotReadSwitchStorage,
      start: {SnapshotReadSwitchStorage, :start_link, [%{}]}
    })

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)
  end

  defp await_background_variant(original_id, attempts \\ 200)

  defp await_background_variant(original_id, attempts) when attempts > 1 do
    original = Repo.get!(AssetRecord, original_id)

    case original.metadata["web_asset_id"] do
      variant_id when is_integer(variant_id) ->
        {original, Repo.get!(AssetRecord, variant_id)}

      _missing ->
        Process.sleep(25)
        await_background_variant(original_id, attempts - 1)
    end
  end

  defp await_background_variant(original_id, 1) do
    original = Repo.get!(AssetRecord, original_id)
    flunk("Scene background variant was not linked: #{inspect(original.metadata)}")
  end

  defp register_storage_cleanup(asset) do
    extension = extension_for(asset.content_type)
    canonical_key = blob_key(asset.project_id, asset.blob_hash, extension)

    on_exit(fn ->
      Storage.delete(asset.key)
      Storage.adapter().delete(canonical_key)
    end)
  end

  defp extension_for("image/jpeg"), do: "jpg"
  defp extension_for(content_type), do: content_type |> String.split("/") |> List.last()

  defp forward_traces(test_pid) do
    receive do
      :stop ->
        :ok

      message ->
        send(test_pid, message)
        forward_traces(test_pid)
    end
  end

  defp flush_scene_storage_io do
    receive do
      {:scene_storage_io, _operation, _key} -> flush_scene_storage_io()
    after
      0 -> :ok
    end
  end

  defp asset_key(project_id, filename) do
    "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{filename}"
  end

  defp blob_key(project_id, hash, extension) do
    "projects/#{project_id}/blobs/#{hash}.#{extension}"
  end

  defp sha256(binary) do
    :sha256
    |> :crypto.hash(binary)
    |> Base.encode16(case: :lower)
  end
end
