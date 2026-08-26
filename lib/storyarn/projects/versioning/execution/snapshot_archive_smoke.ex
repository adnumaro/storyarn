defmodule Storyarn.Projects.Versioning.SnapshotArchiveSmoke do
  @moduledoc """
  Runs the read-only snapshot archive provider smoke inside a running release.

  The smoke verifies exact multipart inventory access, a complete signed GET,
  its incremental SHA-256 digest, the signed response headers, and a byte-range
  GET. It never prints the signed bearer URL or mutates provider state.
  """

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Repo

  require Logger

  @max_archive_bytes 300 * 1024 * 1024
  @probe_bytes 64
  @smoke_filename "storyarn-snapshot-archive-smoke.zip"
  @cache_control "private, no-store, no-transform"
  @hash_private_key :storyarn_snapshot_archive_smoke_hash
  @bytes_private_key :storyarn_snapshot_archive_smoke_bytes
  @prefix_private_key :storyarn_snapshot_archive_smoke_prefix

  @type result :: %{
          snapshot_id: pos_integer(),
          size_bytes: pos_integer(),
          checks: [atom()]
        }

  @doc """
  Runs the fail-closed smoke for one persisted, ready v2 snapshot.

  This function is release-safe and expects the application and repository to
  already be running, as they are when invoked through the release `rpc`
  command.
  """
  @spec run!(pos_integer()) :: result()
  def run!(snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0 do
    ensure!(Storage.external_upload?(), "The real S3-compatible production storage adapter is not configured.")

    snapshot = Repo.get(ProjectSnapshot, snapshot_id) || raise("Snapshot not found.")
    expected = verified_archive!(snapshot)
    verify_multipart_inventory_access!(snapshot.project_id)
    signed_url = signed_url!(expected.storage_key)

    full_response = provider_get!(signed_url, into: &accumulate_full_body/2)
    full_prefix = verify_full_response!(full_response, expected)

    range_end = min(expected.size_bytes, @probe_bytes) - 1
    range_signed_url = signed_url!(expected.storage_key)

    range_response =
      provider_get!(range_signed_url,
        headers: [{"range", "bytes=0-#{range_end}"}]
      )

    verify_range_response!(range_response, expected, full_prefix, range_end)

    result = %{
      snapshot_id: snapshot.id,
      size_bytes: expected.size_bytes,
      checks: [:multipart_inventory, :full_get, :sha256, :headers, :range]
    }

    Logger.info(
      "Snapshot archive provider smoke succeeded: " <>
        "snapshot_id=#{snapshot.id} size_bytes=#{expected.size_bytes}"
    )

    result
  end

  def run!(_snapshot_id), do: raise(ArgumentError, "snapshot_id must be a positive integer")

  defp verify_multipart_inventory_access!(project_id) do
    token = 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    key = project_id |> SnapshotArchiveStorage.staging_prefix(token) |> SnapshotArchiveStorage.archive_key()

    case Storage.incomplete_multipart_upload_count(key, max_uploads: 100) do
      {:ok, 0} -> :ok
      {:ok, _unexpected_count} -> raise("The provider multipart inventory probe was not empty.")
      {:error, _reason} -> raise("The provider did not permit exact multipart inventory inspection.")
    end
  rescue
    _exception ->
      reraise RuntimeError,
              [message: "The provider did not permit exact multipart inventory inspection."],
              __STACKTRACE__
  end

  defp verified_archive!(%ProjectSnapshot{
         project_id: project_id,
         format_version: 2,
         mode: "full",
         lifecycle_state: "ready",
         integrity_state: "verified",
         object_prefix: object_prefix,
         archive_storage_key: storage_key,
         archive_size_bytes: size_bytes,
         archive_checksum: checksum
       }) do
    validate_archive_size!(size_bytes)
    validate_archive_key!(project_id, object_prefix, storage_key)
    validate_archive_checksum!(checksum)

    %{storage_key: storage_key, size_bytes: size_bytes, checksum: checksum}
  end

  defp verified_archive!(%ProjectSnapshot{}), do: invalid_archive!()

  defp validate_archive_size!(size_bytes)
       when is_integer(size_bytes) and size_bytes > 0 and size_bytes <= @max_archive_bytes, do: :ok

  defp validate_archive_size!(size_bytes) when is_integer(size_bytes) and size_bytes > @max_archive_bytes do
    raise("Snapshot archive exceeds the #{@max_archive_bytes}-byte smoke-test safety limit.")
  end

  defp validate_archive_size!(_size_bytes), do: invalid_archive!()

  defp validate_archive_key!(project_id, object_prefix, storage_key)
       when is_integer(project_id) and project_id > 0 and is_binary(object_prefix) and is_binary(storage_key) do
    if SnapshotArchiveStorage.ready_archive_key?(project_id, object_prefix, storage_key),
      do: :ok,
      else: invalid_archive!()
  end

  defp validate_archive_key!(_project_id, _object_prefix, _storage_key), do: invalid_archive!()

  defp validate_archive_checksum!(checksum) when is_binary(checksum) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, checksum), do: :ok, else: invalid_archive!()
  end

  defp validate_archive_checksum!(_checksum), do: invalid_archive!()

  defp invalid_archive! do
    raise("Snapshot must be a verified, ready v2 full snapshot with canonical archive metadata.")
  end

  defp signed_url!(storage_key) do
    case Storage.presigned_download_url(storage_key, "application/zip",
           expires_in: Versioning.project_snapshot_download_signed_url_ttl_seconds(),
           filename: @smoke_filename
         ) do
      {:ok, signed_url} when is_binary(signed_url) -> validate_signed_url!(signed_url)
      _error -> raise("The configured provider did not issue a signed download URL.")
    end
  rescue
    _exception ->
      reraise RuntimeError,
              [message: "The configured provider did not issue a signed download URL."],
              __STACKTRACE__
  end

  defp validate_signed_url!(signed_url) do
    case URI.parse(signed_url) do
      %URI{scheme: "https", host: host, query: query, userinfo: nil, fragment: nil}
      when is_binary(host) and host != "" and is_binary(query) and query != "" ->
        signed_url

      _invalid ->
        raise("The configured provider did not issue a secure signed download URL.")
    end
  end

  defp provider_get!(signed_url, opts) do
    request_opts =
      [
        raw: true,
        compressed: false,
        redirect: false,
        retry: false,
        receive_timeout: 60_000,
        connect_options: [timeout: 10_000]
      ] ++ opts

    case Req.get(signed_url, request_opts) do
      {:ok, %Req.Response{} = response} -> response
      {:error, _reason} -> raise("The provider GET request failed.")
    end
  rescue
    _exception -> reraise RuntimeError, [message: "The provider GET request failed."], __STACKTRACE__
  end

  defp accumulate_full_body({:data, data}, {request, response}) when is_binary(data) do
    hash =
      response
      |> Req.Response.get_private(@hash_private_key, :crypto.hash_init(:sha256))
      |> :crypto.hash_update(data)

    bytes = Req.Response.get_private(response, @bytes_private_key, 0) + byte_size(data)
    prefix = response |> Req.Response.get_private(@prefix_private_key, "") |> append_probe(data)

    response =
      response
      |> Req.Response.put_private(@hash_private_key, hash)
      |> Req.Response.put_private(@bytes_private_key, bytes)
      |> Req.Response.put_private(@prefix_private_key, prefix)

    {:cont, {request, response}}
  end

  defp verify_full_response!(response, expected) do
    ensure!(response.status == 200, "Provider full GET did not return HTTP 200.")
    verify_common_headers!(response)
    require_header!(response, "content-length", Integer.to_string(expected.size_bytes))

    bytes = Req.Response.get_private(response, @bytes_private_key, 0)
    ensure!(bytes == expected.size_bytes, "Provider full GET size did not match the snapshot row.")

    digest =
      response
      |> Req.Response.get_private(@hash_private_key)
      |> finalize_hash!()

    ensure!(digest == expected.checksum, "Provider full GET SHA-256 did not match the snapshot row.")
    Req.Response.get_private(response, @prefix_private_key, "")
  end

  defp verify_range_response!(response, expected, full_prefix, range_end) do
    expected_length = range_end + 1

    ensure!(response.status == 206, "Provider Range GET did not return HTTP 206.")
    verify_common_headers!(response)
    require_header!(response, "accept-ranges", "bytes")
    require_header!(response, "content-length", Integer.to_string(expected_length))

    require_header!(
      response,
      "content-range",
      "bytes 0-#{range_end}/#{expected.size_bytes}"
    )

    ensure!(
      is_binary(response.body) and byte_size(response.body) == expected_length,
      "Provider Range GET returned an unexpected body length."
    )

    ensure!(response.body == full_prefix, "Provider Range GET bytes did not match the full archive.")
  end

  defp verify_common_headers!(response) do
    require_header!(response, "content-type", "application/zip")
    require_header!(response, "cache-control", @cache_control)

    require_header!(
      response,
      "content-disposition",
      ~s(attachment; filename="#{@smoke_filename}")
    )
  end

  defp require_header!(response, name, expected) do
    ensure!(
      Req.Response.get_header(response, name) == [expected],
      "Provider response header #{name} did not match the signed contract."
    )
  end

  defp append_probe(prefix, _data) when byte_size(prefix) >= @probe_bytes, do: prefix

  defp append_probe(prefix, data) do
    remaining = @probe_bytes - byte_size(prefix)
    prefix <> binary_part(data, 0, min(byte_size(data), remaining))
  end

  defp finalize_hash!(nil), do: raise("Provider full GET returned no body.")
  defp finalize_hash!(hash), do: hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

  defp ensure!(true, _message), do: :ok
  defp ensure!(false, message), do: raise(message)
end
