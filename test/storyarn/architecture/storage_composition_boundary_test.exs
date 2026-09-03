defmodule Storyarn.Architecture.StorageCompositionBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Workspaces.Banner.Adapters.Storage.Port

  @public_target "lib/storyarn/platform/object_storage.ex"
  @approved_consumers [
    "lib/storyarn/application.ex",
    "lib/storyarn/flows/versioning/adapters/storage/hashing.ex",
    "lib/storyarn/flows/versioning/adapters/storage/locks.ex",
    "lib/storyarn/flows/versioning/adapters/storage/objects.ex",
    "lib/storyarn/projects/assets/adapters/storage/hash.ex",
    "lib/storyarn/projects/assets/adapters/storage/key_lock.ex",
    "lib/storyarn/projects/assets/adapters/storage/storage.ex",
    "lib/storyarn/scenes/assets/adapters/storage/hashing.ex",
    "lib/storyarn/scenes/assets/adapters/storage/locks.ex",
    "lib/storyarn/scenes/assets/adapters/storage/objects.ex",
    "lib/storyarn/scenes/versioning/adapters/storage/objects.ex",
    "lib/storyarn/sheets/assets/adapters/storage/hashing.ex",
    "lib/storyarn/sheets/assets/adapters/storage/locks.ex",
    "lib/storyarn/sheets/assets/adapters/storage/objects.ex",
    "lib/storyarn/sheets/versioning/adapters/storage/objects.ex",
    "lib/storyarn_web/private_download.ex",
    "lib/storyarn_web/private_media.ex"
  ]

  @platform_sources [
    "lib/storyarn/platform/object_storage.ex"
    | Path.wildcard("lib/storyarn/platform/object_storage/**/*.ex")
  ]

  @production_sources Path.wildcard("lib/**/*.ex")

  @stable_public_functions [
    abort_incomplete_multipart_upload: 2,
    abort_incomplete_multipart_uploads: 1,
    abort_incomplete_multipart_uploads: 2,
    canonical_key?: 1,
    canonical_prefix?: 1,
    child_specs: 0,
    copy: 2,
    copy_if_absent: 2,
    copy_if_absent_or_stream: 4,
    delete: 1,
    delete_if_matches: 2,
    download: 1,
    external_upload?: 0,
    fresh_request_deadline: 0,
    get_url: 1,
    incomplete_multipart_upload_count: 1,
    incomplete_multipart_upload_count: 2,
    incomplete_multipart_upload_state: 2,
    incomplete_multipart_upload_summary: 1,
    incomplete_multipart_upload_summary: 2,
    key_from_url: 1,
    list_incomplete_multipart_uploads: 1,
    list_incomplete_multipart_uploads: 2,
    list_prefix: 1,
    list_prefix: 2,
    list_prefix_metadata: 1,
    list_prefix_metadata: 2,
    multipart_transfer_chunk_size_bytes: 0,
    multipart_upload_part_deadline_ms: 0,
    multipart_upload_total_deadline_ms: 0,
    namespace_fingerprint: 0,
    object_probe: 1,
    presigned_download_url: 2,
    presigned_download_url: 3,
    presigned_upload_url: 2,
    presigned_upload_url: 3,
    put_if_absent: 3,
    sha256_chunks: 1,
    stat: 1,
    stream: 3,
    stream: 4,
    transact_with_storage_handoff: 2,
    transact_with_storage_handoff: 3,
    transact_with_storage_key_admission: 2,
    transact_with_storage_key_admission: 3,
    upload: 3,
    upload_stream: 3,
    with_operation_deadline: 1,
    with_operation_deadline: 2,
    with_session_lock: 2,
    with_session_lock: 3,
    with_storage_key_lock: 2,
    with_storage_key_lock: 3,
    with_storage_key_locks: 2,
    with_storage_key_locks: 3,
    transact_with_storage_key_locks: 2,
    transact_with_storage_key_locks: 3,
    wrapper_owned_transaction_lock_held?: 1,
    write_operation_deadline: 0
  ]

  @provider_callbacks [
    abort_incomplete_multipart_upload: 2,
    abort_incomplete_multipart_uploads: 2,
    copy: 2,
    copy_if_absent: 2,
    delete: 1,
    delete_if_matches: 2,
    download: 1,
    get_url: 1,
    incomplete_multipart_upload_count: 2,
    incomplete_multipart_upload_state: 2,
    incomplete_multipart_upload_summary: 2,
    key_from_url: 1,
    list_incomplete_multipart_uploads: 2,
    list_prefix: 2,
    list_prefix_metadata: 2,
    namespace_fingerprint: 0,
    object_probe: 1,
    presigned_download_url: 3,
    presigned_upload_url: 3,
    put_if_absent: 3,
    stat: 1,
    stream: 4,
    upload: 3,
    upload_stream: 3
  ]

  test "Workspaces consumes the public Platform mechanism through its own port" do
    assert Application.fetch_env!(:storyarn, Port) == [adapter: ObjectStorage]

    config = File.read!("config/config.exs")
    assert config =~ "config :storyarn, ObjectStorage, multipart_upload_part_deadline_ms:"
    refute config =~ "config :storyarn, :\"Elixir.Storyarn.Projects.Assets.Storage\""
  end

  test "the ratchet exposes one ObjectStorage contract to exactly the reviewed consumers" do
    policy = DependencyPolicy.load!("config/architecture_boundaries.exs")

    assert Enum.any?(policy.additional_durable_contract_targets, &(&1.target == @public_target))
    refute @public_target in policy.globally_allowed_technical_targets
    assert policy.migration_exceptions == []

    consumers =
      policy.durable_contracts
      |> Enum.filter(&(&1.target == @public_target))
      |> Enum.map(& &1.source)
      |> Enum.sort()

    assert consumers == Enum.sort(@approved_consumers)

    facade_denials =
      Enum.filter(policy.path_denials, &(&1.source_root == @public_target))

    assert facade_denials != []

    assert Enum.all?(facade_denials, fn denial ->
             String.starts_with?(denial.target_root, "lib/storyarn/platform/") and
               not String.starts_with?(denial.target_root, "lib/storyarn/platform/object_storage/")
           end)
  end

  test "the public facade and provider behaviour cannot change accidentally" do
    assert :functions |> ObjectStorage.__info__() |> Enum.sort() == Enum.sort(@stable_public_functions)
    assert :callbacks |> ObjectStorage.behaviour_info() |> Enum.sort() == Enum.sort(@provider_callbacks)
    refute function_exported?(ObjectStorage, :adapter, 0)
  end

  test "production code reaches only the public facade from the approved seams" do
    external_sources = @production_sources -- @platform_sources

    consumers =
      external_sources
      |> Enum.filter(&(File.read!(&1) =~ "Storyarn.Platform.ObjectStorage"))
      |> Enum.sort()

    assert consumers == Enum.sort(@approved_consumers)

    private_reference_violations =
      Enum.filter(external_sources, fn path ->
        Regex.match?(
          ~r/\bStoryarn\.Platform\.ObjectStorage\.(?:Adapters|Hashing|KeyLock)\b/,
          File.read!(path)
        )
      end)

    assert private_reference_violations == [],
           "ObjectStorage providers, hashing and lock engine are private to Platform: " <>
             inspect(private_reference_violations)

    adapter_escape_violations =
      Enum.filter(external_sources, fn path ->
        Regex.match?(~r/\b(?:ObjectStorage|Storage)\.adapter\s*\(/, File.read!(path))
      end)

    assert adapter_escape_violations == [],
           "Consumers must not obtain the configured provider module: " <>
             inspect(adapter_escape_violations)
  end

  test "the private mechanism remains neutral about consumer namespaces and workflows" do
    private_violations =
      @platform_sources
      |> List.delete(@public_target)
      |> Enum.filter(fn path ->
        Regex.match?(
          ~r/\bprojects\/|\bworkspaces\/|\bsnapshots?\b|\breachability\b|\bretention\b/i,
          File.read!(path)
        )
      end)

    assert private_violations == [],
           "Platform ObjectStorage must own mechanism, never consumer keys or lifecycle policy: " <>
             inspect(private_violations)

    facade_source = File.read!(@public_target)

    refute Regex.match?(~r/\bprojects\/|\bworkspaces\/|\bsnapshots?\b/i, facade_source),
           "The ObjectStorage facade cannot contain a consumer key grammar or workflow"
  end
end
