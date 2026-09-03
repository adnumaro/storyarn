defmodule Storyarn.Projects.Assets.StorageTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.MultipartStorageSpy
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest

  @legacy_config_key :"Elixir.Storyarn.Projects.Assets.Storage"

  defmodule NoMultipartInventoryAdapter do
    @moduledoc false
  end

  defmodule ExactMultipartAdapter do
    @moduledoc false

    def list_incomplete_multipart_uploads(key, opts) do
      send(self(), {:exact_multipart_inventory_dispatched, key, opts})

      Process.get(
        {__MODULE__, :inventory_result},
        {:ok, %{uploads: [%{key: key, upload_id: "opaque-upload-id"}], inventory_complete: true}}
      )
    end

    def abort_incomplete_multipart_upload(key, upload_id) do
      send(self(), {:exact_multipart_abort_dispatched, key, upload_id})
      Process.get({__MODULE__, :abort_result}, :ok)
    end

    def incomplete_multipart_upload_state(key, upload_id) do
      send(self(), {:exact_multipart_state_dispatched, key, upload_id})
      Process.get({__MODULE__, :state_result}, {:ok, :absent_now})
    end
  end

  defmodule WriteFenceAdapter do
    @moduledoc false

    def upload(key, _data, _content_type), do: dispatch(:upload, key, {:ok, "stored"})
    def upload_stream(key, _chunks, _content_type), do: dispatch(:upload_stream, key, {:ok, "stored"})
    def put_if_absent(key, _data, _content_type), do: dispatch(:put_if_absent, key, {:ok, "stored", true})

    def presigned_upload_url(key, _content_type, _opts), do: dispatch(:presigned_upload_url, key, {:ok, "signed", %{}})

    def copy(_source_key, destination_key), do: dispatch(:copy, destination_key, :ok)

    def copy_if_absent(_source_key, destination_key), do: dispatch(:copy_if_absent, destination_key, {:ok, true})

    def delete(key), do: dispatch(:delete, key, :ok)

    defp dispatch(operation, key, result) do
      send(self(), {:write_fence_adapter, operation, key})

      case Process.get({__MODULE__, :after_dispatch}) do
        callback when is_function(callback, 0) ->
          Process.delete({__MODULE__, :after_dispatch})
          callback.()

        _none ->
          :ok
      end

      Process.get({__MODULE__, operation, :result}, result)
    end
  end

  defmodule OverwritingWriteFenceAdapter do
    @moduledoc false

    def upload(key, bytes, content_type), do: after_write(key, Local.upload(key, bytes, content_type))

    # Model a provider's successful overwrite without changing Local's
    # exclusive-create stream implementation.
    def upload_stream(key, chunks, content_type) do
      bytes = chunks |> Enum.to_list() |> IO.iodata_to_binary()
      after_write(key, Local.upload(key, bytes, content_type))
    end

    def copy(source, destination), do: after_write(destination, Local.copy(source, destination))

    def delete(key) do
      send(self(), {:overwriting_adapter_delete, key})
      Local.delete(key)
    end

    defp after_write(key, result) do
      Process.get({__MODULE__, :after_write}).(key)
      result
    end
  end

  test "keeps the legacy multipart deadline key as a deployment compatibility fallback" do
    current_config = Application.get_env(:storyarn, ObjectStorage)
    legacy_config = Application.get_env(:storyarn, @legacy_config_key)

    Application.delete_env(:storyarn, ObjectStorage)
    Application.put_env(:storyarn, @legacy_config_key, multipart_upload_part_deadline_ms: 1_234)

    on_exit(fn ->
      restore_env(ObjectStorage, current_config)
      restore_env(@legacy_config_key, legacy_config)
    end)

    assert Storage.multipart_upload_part_deadline_ms() == 1_234
  end

  test "nested operation deadlines keep the earliest budget and restore their caller" do
    ObjectStorage.with_operation_deadline(5_000, fn ->
      outer_deadline = ObjectStorage.write_operation_deadline()

      ObjectStorage.with_operation_deadline(500, fn ->
        inner_deadline = ObjectStorage.write_operation_deadline()
        assert inner_deadline < outer_deadline
      end)

      assert ObjectStorage.write_operation_deadline() == outer_deadline
    end)
  end

  @test_dir "test/tmp/storage_dispatch"

  setup do
    original_config = Application.get_env(:storyarn, :storage, [])

    Application.put_env(:storyarn, :storage,
      adapter: :local,
      upload_dir: @test_dir,
      public_path: "/dispatch-uploads"
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_config)
      File.rm_rf(@test_dir)
    end)

    %{}
  end

  # =============================================================================
  # provider selection
  # =============================================================================

  describe "provider selection" do
    test "uses the local provider when configured as :local" do
      Application.put_env(:storyarn, :storage, adapter: :local)
      refute Storage.external_upload?()
    end

    test "uses the external provider when configured as :r2" do
      original = Application.get_env(:storyarn, :storage, [])
      Application.put_env(:storyarn, :storage, adapter: :r2)

      assert Storage.external_upload?()

      Application.put_env(:storyarn, :storage, original)
    end

    test "defaults to the local provider when no adapter is configured" do
      Application.put_env(:storyarn, :storage, [])
      refute Storage.external_upload?()
    end

    test "reports direct external upload support without leaking the concrete adapter to callers" do
      Application.put_env(:storyarn, :storage, adapter: :local)
      refute Storage.external_upload?()

      Application.put_env(:storyarn, :storage, adapter: :r2)
      assert Storage.external_upload?()
    end
  end

  describe "multipart cleanup policy" do
    test "covers the total multipart writer deadline after second-precision clock truncation" do
      deadline_ms = Storage.multipart_upload_total_deadline_ms()
      quiescence_ms = Storage.multipart_cleanup_quiescence_seconds() * 1_000

      assert quiescence_ms >= deadline_ms + 1_000
    end

    test "recognizes only exact restore-reservation blob upload keys" do
      lease_token = "3abf435a-c086-4801-9b91-5a49a440f917"
      hash = String.duplicate("a", 64)
      key = "projects/42/storage-reservations/v1/restore-staging/#{lease_token}/blobs/#{hash}.png"

      assert Storage.multipart_cleanup_key?(key)

      refute Storage.multipart_cleanup_key?(
               "projects/42/storage-reservations/v1/snapshot-build/#{lease_token}/blobs/#{hash}.png"
             )

      refute Storage.multipart_cleanup_key?(
               "projects/42/storage-reservations/v1/restore-staging/#{lease_token}/project.json"
             )

      refute Storage.multipart_cleanup_key?(key <> "/extra")
      refute Storage.multipart_cleanup_key?(String.replace(key, lease_token, String.upcase(lease_token)))
      refute Storage.multipart_cleanup_key?(String.replace(key, "projects/42", "projects/0"))
    end

    test "blocks every internal write destination after durable multipart handoff" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      persist_multipart_handoff!("__storyarn_force_delete__:" <> key)
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)

      assert {:error, :storage_key_cleanup_handed_off} = Storage.upload(key, "bytes", "application/zip")

      assert {:error, :storage_key_cleanup_handed_off} =
               Storage.upload_stream(key, [{:ok, "bytes"}], "application/zip")

      assert {:error, :storage_key_cleanup_handed_off} =
               Storage.put_if_absent(key, "bytes", "application/zip")

      assert {:error, :storage_key_cleanup_handed_off} =
               Storage.presigned_upload_url(key, "application/zip")

      assert {:error, :storage_key_cleanup_handed_off} = Storage.copy("source", key)
      assert {:error, :storage_key_cleanup_handed_off} = Storage.copy_if_absent("source", key)

      assert {:error, :storage_key_cleanup_handed_off} =
               Storage.copy_if_absent_or_stream("source", key, 5, "application/zip")

      refute_received {:write_fence_adapter, _, _}
    end

    test "never issues a bearer PUT for cleanup-protected keys even before handoff" do
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)
      token = Ecto.UUID.generate()
      hash = String.duplicate("a", 64)

      keys = [
        "projects/1/snapshots/archives/v2/staging/BearerFenceTok01/snapshot.zip",
        "projects/1/snapshots/archives/v2/ready/BearerFenceTok01/manifest.json",
        "projects/1/storage-reservations/v1/restore-staging/#{token}/blobs/#{hash}.png",
        "workspace-snapshot-imports/v1/1/#{token}/snapshot.zip",
        "workspace-snapshot-imports/v1/1/#{token}/blobs/#{hash}.png"
      ]

      for key <- keys do
        assert {:error, :presigned_upload_requires_server_upload} =
                 Storage.presigned_upload_url(key, "application/zip", expires_in: 3_600, content_length: 5)
      end

      refute_received {:write_fence_adapter, :presigned_upload_url, _key}
    end

    test "removes a newly created conditional object when cleanup handoff commits during the provider write" do
      key = "projects/1/snapshots/archives/v2/staging/RaceFenceToken12/snapshot.zip"
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)
      Process.put({WriteFenceAdapter, :after_dispatch}, fn -> persist_multipart_handoff!(key) end)

      assert {:error, :storage_key_cleanup_handed_off} =
               Storage.put_if_absent(key, "bytes", "application/zip")

      assert_received {:write_fence_adapter, :put_if_absent, ^key}
      assert_received {:write_fence_adapter, :delete, ^key}
    end

    test "unconditional writes never delete a pre-existing destination after cleanup handoff" do
      source_key = "overwrite-fence/source.png"
      assert {:ok, _url} = Local.upload(source_key, "replacement bytes", "image/png")
      Application.put_env(:storyarn, :storage, adapter: OverwritingWriteFenceAdapter, upload_dir: @test_dir)

      Process.put({OverwritingWriteFenceAdapter, :after_write}, fn key -> persist_multipart_handoff!(key) end)

      for {operation, write_fun} <- [
            {:upload, fn key -> Storage.upload(key, "replacement bytes", "image/png") end},
            {:upload_stream, fn key -> Storage.upload_stream(key, ["replacement bytes"], "image/png") end},
            {:copy, fn key -> Storage.copy(source_key, key) end}
          ],
          namespace <- [:asset, :blob] do
        key =
          case namespace do
            :asset -> "projects/1/assets/#{Ecto.UUID.generate()}/#{operation}.png"
            :blob -> "projects/1/blobs/#{Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)}.png"
          end

        assert {:ok, _url} = Local.upload(key, "previously owned bytes", "image/png")
        assert {:error, :storage_key_cleanup_handed_off} = write_fun.(key)
        refute_received {:overwriting_adapter_delete, ^key}
        assert {:ok, "replacement bytes"} = Local.download(key)
        assert Repo.exists?(from request in StorageCleanupRequest, where: ^key in request.storage_keys)
      end
    end

    test "never deletes a pre-existing object after a conditional write reports not created" do
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)

      for {operation, key, write_fun} <- [
            {:put_if_absent, "projects/1/snapshots/archives/v2/staging/NoOpFenceToken01/snapshot.zip",
             fn key -> Storage.put_if_absent(key, "bytes", "application/zip") end},
            {:copy_if_absent, "projects/1/snapshots/archives/v2/staging/NoOpFenceToken02/snapshot.zip",
             fn key -> Storage.copy_if_absent("source", key) end},
            {:copy_if_absent, "projects/1/snapshots/archives/v2/staging/NoOpFenceToken03/snapshot.zip",
             fn key ->
               Storage.copy_if_absent_or_stream("source", key, 5, "application/zip")
             end}
          ] do
        Process.put(
          {WriteFenceAdapter, operation, :result},
          if(operation == :put_if_absent, do: {:ok, "stored", false}, else: {:ok, false})
        )

        Process.put({WriteFenceAdapter, :after_dispatch}, fn -> persist_multipart_handoff!(key) end)

        assert {:error, :storage_key_cleanup_handed_off} = write_fun.(key)
        assert_received {:write_fence_adapter, ^operation, ^key}
        refute_received {:write_fence_adapter, :delete, ^key}
      end
    end

    test "rejects non-canonical write destinations before provider dispatch" do
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)
      invalid_key = "projects/1/snapshots/../escape.zip"

      assert {:error, :invalid_key} = Storage.upload(invalid_key, "bytes", "application/zip")
      assert {:error, :invalid_key} = Storage.upload_stream(invalid_key, ["bytes"], "application/zip")
      assert {:error, :invalid_key} = Storage.put_if_absent(invalid_key, "bytes", "application/zip")
      assert {:error, :invalid_key} = Storage.presigned_upload_url(invalid_key, "application/zip")
      assert {:error, :invalid_key} = Storage.copy("source", invalid_key)
      assert {:error, :invalid_key} = Storage.copy_if_absent("source", invalid_key)

      assert {:error, :invalid_key} =
               Storage.copy_if_absent_or_stream("source", invalid_key, 5, "application/zip")

      refute_received {:write_fence_adapter, _, _}
    end

    test "fences non-multipart destinations owned by a mixed cleanup receipt" do
      multipart_key = "projects/1/snapshots/archives/v2/staging/MixedFenceToken1/snapshot.zip"
      blob_key = "projects/1/blobs/#{String.duplicate("a", 64)}.png"
      persist_multipart_handoff!([multipart_key, "__storyarn_force_delete__:" <> blob_key])
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)

      assert {:error, :storage_key_cleanup_handed_off} = Storage.upload(blob_key, "bytes", "image/png")
      refute_received {:write_fence_adapter, _, _}
    end

    test "releases reusable blob keys after their cleanup request is consumed" do
      multipart_key = "projects/1/snapshots/archives/v2/staging/ReleasedFenceTok/snapshot.zip"
      blob_key = "projects/1/blobs/#{String.duplicate("b", 64)}.png"
      request = persist_multipart_handoff!([multipart_key, "__storyarn_force_delete__:" <> blob_key])
      Repo.delete!(request)
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)

      assert {:ok, "stored"} = Storage.upload(blob_key, "bytes", "image/png")
      assert_received {:write_fence_adapter, :upload, ^blob_key}
    end
  end

  describe "canonical_prefix?/1" do
    test "requires exactly one trailing slash" do
      assert Storage.canonical_prefix?("projects/1/snapshots/")
      refute Storage.canonical_prefix?("projects/1/snapshots")
      refute Storage.canonical_prefix?("projects/1/snapshots//")

      assert {:error, :invalid_prefix} =
               Storage.list_prefix("projects/1/snapshots//")
    end
  end

  # =============================================================================
  # upload/3
  # =============================================================================

  describe "upload/3" do
    test "delegates to configured adapter and returns URL" do
      key = "dispatch_test_#{System.unique_integer([:positive])}/file.txt"
      assert {:ok, url} = Storage.upload(key, "test data", "text/plain")
      assert url == "/dispatch-uploads/#{key}"

      # Verify the file was actually written
      path = Path.join(@test_dir, key)
      assert File.exists?(path)
      assert File.read!(path) == "test data"
    end

    test "handles binary content types" do
      key = "dispatch_binary_#{System.unique_integer([:positive])}/image.png"
      binary = <<137, 80, 78, 71, 13, 10, 26, 10>>
      assert {:ok, _url} = Storage.upload(key, binary, "image/png")

      path = Path.join(@test_dir, key)
      assert File.read!(path) == binary
    end
  end

  describe "copy_if_absent/2" do
    test "delegates conditional copies and preserves the first destination bytes" do
      source_key = "dispatch_copy/source.txt"
      destination_key = "dispatch_copy/destination.txt"

      assert {:ok, _url} = Storage.upload(source_key, "first", "text/plain")
      assert {:ok, true} = Storage.copy_if_absent(source_key, destination_key)

      assert {:ok, _url} = Storage.upload(source_key, "second", "text/plain")
      assert {:ok, false} = Storage.copy_if_absent(source_key, destination_key)
      assert {:ok, "first"} = Storage.download(destination_key)
    end
  end

  describe "abort_incomplete_multipart_uploads/2" do
    test "skips keys that Projects policy never writes with multipart upload" do
      assert {:ok, 0} =
               Storage.abort_incomplete_multipart_uploads(
                 "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/.storyarn-copy/copy-token",
                 []
               )
    end

    test "dispatches approved keys through the neutral provider contract" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      opts = [max_uploads: 7]
      Application.put_env(:storyarn, :storage, adapter: MultipartStorageSpy)

      assert {:ok, 17} = Storage.abort_incomplete_multipart_uploads(key, opts)
      assert_received {:multipart_abort_dispatched, ^key, ^opts}
    end

    test "treats a non-multipart adapter as an empty exact inventory" do
      assert {:ok, 0} =
               Storage.abort_incomplete_multipart_uploads(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "rejects unsafe keys and options before dispatch" do
      assert {:error, :invalid_multipart_cleanup_request} =
               Storage.abort_incomplete_multipart_uploads("projects/1/../snapshot.zip")

      assert {:error, :invalid_multipart_cleanup_request} =
               Storage.abort_incomplete_multipart_uploads("projects/1/snapshot.zip", %{limit: 1})
    end
  end

  describe "exact multipart upload references" do
    setup do
      Application.put_env(:storyarn, :storage, adapter: ExactMultipartAdapter)
      :ok
    end

    test "dispatches exact key and upload id through the Projects storage policy" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      upload_id = "opaque-upload-id"
      opts = [batch_size: 7]

      assert {:ok,
              %{
                uploads: [%{key: ^key, upload_id: ^upload_id}],
                inventory_complete: true
              }} = Storage.list_incomplete_multipart_uploads(key, opts)

      assert_received {:exact_multipart_inventory_dispatched, ^key, ^opts}

      assert :ok = Storage.abort_incomplete_multipart_upload(key, upload_id)
      assert_received {:exact_multipart_abort_dispatched, ^key, ^upload_id}

      assert {:ok, :absent_now} = Storage.incomplete_multipart_upload_state(key, upload_id)
      assert_received {:exact_multipart_state_dispatched, ^key, ^upload_id}
    end

    test "rejects unsafe keys and upload ids before provider dispatch" do
      valid_key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      assert {:error, :invalid_multipart_inventory_request} =
               Storage.list_incomplete_multipart_uploads("projects/1/../snapshot.zip")

      assert {:error, :invalid_multipart_upload_reference} =
               Storage.abort_incomplete_multipart_upload("projects/1/private.bin", "upload-id")

      assert {:error, :invalid_multipart_upload_reference} =
               Storage.abort_incomplete_multipart_upload(valid_key, "")

      assert {:error, :invalid_multipart_upload_reference} =
               Storage.incomplete_multipart_upload_state(valid_key, String.duplicate("u", 4_097))

      refute_received {:exact_multipart_inventory_dispatched, _, _}
      refute_received {:exact_multipart_abort_dispatched, _, _}
      refute_received {:exact_multipart_state_dispatched, _, _}
    end

    test "fails closed on malformed, duplicate, or oversized provider inventory" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      invalid_results = [
        {:ok, %{uploads: [%{key: key, upload_id: "upload-1"}]}},
        {:ok,
         %{
           uploads: [%{key: "projects/2/private.bin", upload_id: "upload-1"}],
           inventory_complete: true
         }},
        {:ok,
         %{
           uploads: [
             %{key: key, upload_id: "duplicate"},
             %{key: key, upload_id: "duplicate"}
           ],
           inventory_complete: true
         }},
        {:ok,
         %{
           uploads: [%{key: key, upload_id: String.duplicate("u", 4_097)}],
           inventory_complete: true
         }},
        {:ok,
         %{
           uploads:
             Enum.map(1..101, fn index ->
               %{key: key, upload_id: "upload-#{index}"}
             end),
           inventory_complete: false
         }}
      ]

      Enum.each(invalid_results, fn result ->
        Process.put({ExactMultipartAdapter, :inventory_result}, result)

        assert {:error, :invalid_multipart_inventory_response} =
                 Storage.list_incomplete_multipart_uploads(key)
      end)
    end

    test "collapses private provider failures at the neutral boundary" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      private_value = "private-bucket/#{key}?signature=secret"

      Process.put(
        {ExactMultipartAdapter, :inventory_result},
        {:error, {:http_error, 500, %{body: private_value}}}
      )

      result = Storage.list_incomplete_multipart_uploads(key)

      assert result == {:error, :multipart_inventory_provider_error}
      refute inspect(result) =~ private_value
    end
  end

  describe "incomplete_multipart_upload_count/2" do
    test "fails closed when the configured adapter has no multipart inventory" do
      Application.put_env(:storyarn, :storage, adapter: NoMultipartInventoryAdapter)

      assert {:error, :multipart_inventory_not_supported} =
               Storage.incomplete_multipart_upload_count(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "dispatches approved inventory through the neutral provider contract" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      opts = [max_uploads: 7]
      Application.put_env(:storyarn, :storage, adapter: MultipartStorageSpy)

      assert {:ok, 23} = Storage.incomplete_multipart_upload_count(key, opts)
      assert_received {:multipart_inventory_dispatched, ^key, ^opts}
    end

    test "treats the local non-multipart backend as an exact empty inventory" do
      assert {:ok, 0} =
               Storage.incomplete_multipart_upload_count(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "rejects unsafe keys and options before dispatch" do
      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_count("projects/1/../snapshot.zip")

      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_count("projects/1/snapshot.zip", %{limit: 1})
    end
  end

  describe "incomplete_multipart_upload_summary/2" do
    test "dispatches one bounded global inventory through the neutral provider contract" do
      opts = [max_uploads: 47]
      Application.put_env(:storyarn, :storage, adapter: MultipartStorageSpy)

      assert {:ok,
              %{
                count: 29,
                oldest_initiated_at: ~U[2026-09-01 12:00:00Z],
                inventory_complete: true
              }} = Storage.incomplete_multipart_upload_summary(:all, opts)

      assert_received {:multipart_summary_dispatched, :all, ^opts}
    end

    test "fails closed when the configured adapter has no aggregate inventory" do
      Application.put_env(:storyarn, :storage, adapter: NoMultipartInventoryAdapter)

      assert {:error, :multipart_inventory_not_supported} =
               Storage.incomplete_multipart_upload_summary("projects/")
    end

    test "reports the local backend as a complete empty inventory" do
      assert {:ok, %{count: 0, oldest_initiated_at: nil, inventory_complete: true}} =
               Storage.incomplete_multipart_upload_summary(:all)
    end

    test "rejects unsafe prefixes and options before dispatch" do
      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_summary("projects")

      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_summary("projects//", %{max_uploads: 1})

      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_summary(:everything)
    end

    test "strips extra fields and collapses private provider errors at the neutral boundary" do
      private_value = "private-bucket/projects/42/private.zip?signature=secret"
      Application.put_env(:storyarn, :storage, adapter: MultipartStorageSpy)

      Process.put(
        {MultipartStorageSpy, :multipart_summary_result},
        {:ok,
         %{
           count: 1,
           oldest_initiated_at: ~U[2026-09-01 12:00:00Z],
           inventory_complete: true,
           storage_key: private_value
         }}
      )

      assert {:ok, summary} = Storage.incomplete_multipart_upload_summary(:all)
      refute Map.has_key?(summary, :storage_key)
      refute inspect(summary) =~ private_value

      Process.put(
        {MultipartStorageSpy, :multipart_summary_result},
        {:error, {:http_error, 500, %{body: private_value}}}
      )

      result = Storage.incomplete_multipart_upload_summary(:all)
      assert result == {:error, :multipart_inventory_provider_error}
      refute inspect(result) =~ private_value
    end
  end

  # =============================================================================
  # delete/1
  # =============================================================================

  describe "delete/1" do
    test "delegates to configured adapter and deletes file" do
      key = "dispatch_delete_#{System.unique_integer([:positive])}/file.txt"
      {:ok, _} = Storage.upload(key, "content", "text/plain")

      assert :ok = Storage.delete(key)

      path = Path.join(@test_dir, key)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file" do
      assert :ok = Storage.delete("nonexistent/key.txt")
    end

    test "blocks deletion of recoverable blobs" do
      key = "projects/1/blobs/hash.png"
      {:ok, _url} = Storage.upload(key, "recoverable", "image/png")

      assert {:error, :recoverable_blob} = Storage.delete(key)
      assert File.read!(Path.join(@test_dir, key)) == "recoverable"
    end

    test "rejects non-canonical keys before the adapter can normalize them" do
      canonical_key = "projects/1/blobs/hash.png"
      {:ok, _url} = Storage.upload(canonical_key, "recoverable", "image/png")

      invalid_keys = [
        "projects/1/blobs//hash.png",
        "projects/1//blobs/hash.png",
        "projects//1/blobs/hash.png",
        "projects/1/blobs/hash.png/",
        "/projects/1/blobs/hash.png",
        "projects/1/blobs/./hash.png",
        "projects/1/assets/../blobs/hash.png",
        "projects/1/blobs\\hash.png",
        "projects/1/blobs/hash.png" <> <<0>>
      ]

      for invalid_key <- invalid_keys do
        assert {:error, :invalid_key} = Storage.delete(invalid_key)
      end

      assert File.read!(Path.join(@test_dir, canonical_key)) == "recoverable"
    end
  end

  # =============================================================================
  # get_url/1
  # =============================================================================

  describe "get_url/1" do
    test "delegates to configured adapter and returns public URL" do
      assert Storage.get_url("project/asset.png") == "/dispatch-uploads/project/asset.png"
    end

    test "handles nested paths" do
      assert Storage.get_url("a/b/c/d.txt") == "/dispatch-uploads/a/b/c/d.txt"
    end
  end

  # =============================================================================
  # presigned_upload_url/3
  # =============================================================================

  describe "presigned_upload_url/3" do
    test "preserves presigning outside cleanup-protected namespaces" do
      Application.put_env(:storyarn, :storage, adapter: WriteFenceAdapter)
      key = "projects/1/assets/#{Ecto.UUID.generate()}/image.png"

      assert {:ok, "signed", %{}} = Storage.presigned_upload_url(key, "image/png", content_length: 5)
      assert_received {:write_fence_adapter, :presigned_upload_url, ^key}
    end

    test "delegates to configured adapter" do
      # Local adapter returns :not_supported
      assert {:error, :not_supported} = Storage.presigned_upload_url("key", "text/plain")
    end

    test "accepts optional opts parameter" do
      assert {:error, :not_supported} =
               Storage.presigned_upload_url("key", "text/plain", max_size: 1024)
    end
  end

  describe "presigned_download_url/3" do
    test "uses the adapter only for a bounded canonical attachment request" do
      assert {:error, :not_supported} =
               Storage.presigned_download_url(
                 "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/snapshot.zip",
                 "application/zip",
                 expires_in: 300,
                 filename: "snapshot.zip"
               )
    end

    test "rejects unsafe keys, metadata, filenames, and expiry before delegation" do
      invalid_requests = [
        ["projects/1/../secret", "application/zip", [filename: "snapshot.zip"]],
        ["projects/1/archive.zip", "application/zip\r\ntext/html", [filename: "snapshot.zip"]],
        ["projects/1/archive.zip", "application/zip", [filename: "bad\r\nname.zip"]],
        ["projects/1/archive.zip", "application/zip", [filename: "snapshot.zip", expires_in: 0]],
        ["projects/1/archive.zip", "application/zip", [filename: "snapshot.zip", expires_in: 301]]
      ]

      for [key, content_type, opts] <- invalid_requests do
        assert {:error, :invalid_presigned_download_request} =
                 Storage.presigned_download_url(key, content_type, opts)
      end
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:storyarn, key)
  defp restore_env(key, value), do: Application.put_env(:storyarn, key, value)

  defp persist_multipart_handoff!(storage_key) when is_binary(storage_key), do: persist_multipart_handoff!([storage_key])

  defp persist_multipart_handoff!(storage_keys) when is_list(storage_keys) do
    %StorageCleanupRequest{}
    |> StorageCleanupRequest.changeset(%{
      storage_keys: storage_keys,
      provider_namespace_fingerprint: String.duplicate("a", 64),
      multipart_cleanup_phase: "discover"
    })
    |> Repo.insert!()
  end
end
