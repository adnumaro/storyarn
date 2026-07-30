defmodule Storyarn.Imports.PlanStorage do
  @moduledoc """
  Stores import plans compressed and encrypted in private object storage.

  Each encrypted object contains a versioned envelope bound to its exact
  storage key. Copying an otherwise valid ciphertext to another object key is
  rejected after decryption. The uncompressed JSON size is bounded before
  compression and encryption; configure the default with:

      config :storyarn, Storyarn.Imports.PlanStorage,
        max_json_bytes: 134_217_728

  Calls may override the limit with `:max_json_bytes` for controlled tooling
  and tests.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Vault

  @default_max_json_bytes 128 * 1024 * 1024
  @envelope_magic "STORYARN_IMPORT_PLAN"
  @envelope_version 1
  @binding_nonce_bytes 32
  @binding_digest_bytes 32
  @binding_domain "storyarn:import-plan:storage-key:v1"

  @spec storage_key(pos_integer()) :: String.t()
  def storage_key(project_id) when is_integer(project_id) and project_id > 0 do
    "imports/plans/#{Ecto.UUID.generate()}.plan.enc"
  end

  @spec store(pos_integer(), ImportPlan.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def store(project_id, %ImportPlan{} = plan, opts \\ []) when is_list(opts) do
    project_id
    |> storage_key()
    |> store_at(plan, opts)
  end

  @spec store_at(String.t(), ImportPlan.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def store_at(key, %ImportPlan{} = plan, opts \\ []) when is_binary(key) and is_list(opts) do
    if ImportPlan.error?(plan) do
      {:error, :import_plan_has_errors}
    else
      with {:ok, source_kind} <- encode_source_kind(plan.source_kind),
           {:ok, issue_summary} <- encode_issue_summary(plan.metadata),
           payload = %{
             "format" => to_string(plan.format),
             "parser_version" => plan.parser_version,
             "source_kind" => source_kind,
             "data" => plan.data,
             "issue_summary" => issue_summary
           },
           {:ok, max_json_bytes} <- max_json_bytes(opts),
           {:ok, json_iodata} <- Jason.encode_to_iodata(payload),
           :ok <- validate_json_size(json_iodata, max_json_bytes),
           json = IO.iodata_to_binary(json_iodata),
           compressed = :zlib.gzip(json),
           envelope = bind_to_storage_key(key, compressed),
           {:ok, encrypted} <- Vault.encrypt(envelope),
           {:ok, _private_url} <- Storage.upload(key, encrypted, "application/octet-stream") do
        {:ok, key}
      else
        {:error, :import_plan_too_large} = error -> error
        _error -> {:error, :import_plan_storage_failed}
      end
    end
  end

  @spec load(String.t(), keyword()) :: {:ok, ImportPlan.t()} | {:error, atom()}
  def load(key, opts \\ []) when is_binary(key) and is_list(opts) do
    with {:ok, max_json_bytes} <- max_json_bytes(opts),
         {:ok, encrypted} <- Storage.download(key),
         {:ok, envelope} <- Vault.decrypt(encrypted),
         {:ok, compressed} <- verify_storage_key_binding(key, envelope),
         {:ok, json} <- gunzip(compressed),
         :ok <- validate_json_size(json, max_json_bytes),
         {:ok, payload} when is_map(payload) <- Jason.decode(json),
         {:ok, plan} <- decode_plan(payload) do
      {:ok, plan}
    else
      _error -> {:error, :import_plan_unavailable}
    end
  end

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key), do: Storage.delete(key)

  defp max_json_bytes(opts) do
    configured_limit =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_json_bytes, @default_max_json_bytes)

    case Keyword.get(opts, :max_json_bytes, configured_limit) do
      limit when is_integer(limit) and limit > 0 -> {:ok, limit}
      _invalid -> {:error, :invalid_import_plan_storage_config}
    end
  end

  defp validate_json_size(json, max_json_bytes) when is_binary(json) do
    validate_json_size_bytes(byte_size(json), max_json_bytes)
  end

  defp validate_json_size(json_iodata, max_json_bytes) do
    validate_json_size_bytes(IO.iodata_length(json_iodata), max_json_bytes)
  end

  defp validate_json_size_bytes(size, max_json_bytes) when size <= max_json_bytes, do: :ok

  defp validate_json_size_bytes(_size, _max_json_bytes), do: {:error, :import_plan_too_large}

  defp bind_to_storage_key(key, compressed) do
    nonce = :crypto.strong_rand_bytes(@binding_nonce_bytes)
    binding = storage_key_binding(key, nonce)

    <<@envelope_magic::binary, @envelope_version::unsigned-8, nonce::binary, binding::binary, compressed::binary>>
  end

  defp verify_storage_key_binding(
         key,
         <<@envelope_magic, @envelope_version::unsigned-8, nonce::binary-size(@binding_nonce_bytes),
           stored_binding::binary-size(@binding_digest_bytes), compressed::binary>>
       )
       when byte_size(compressed) > 0 do
    expected_binding = storage_key_binding(key, nonce)

    if Plug.Crypto.secure_compare(expected_binding, stored_binding),
      do: {:ok, compressed},
      else: {:error, :invalid_import_plan_binding}
  end

  defp verify_storage_key_binding(_key, _envelope), do: {:error, :invalid_import_plan_binding}

  defp storage_key_binding(key, nonce) do
    :crypto.hash(:sha256, [@binding_domain, <<0>>, nonce, <<0>>, key])
  end

  defp gunzip(compressed) do
    {:ok, :zlib.gunzip(compressed)}
  rescue
    ErlangError -> {:error, :invalid_import_plan}
  end

  defp decode_plan(%{"format" => format, "parser_version" => parser_version, "data" => data} = payload)
       when is_binary(parser_version) and is_map(data) do
    with {:ok, format} <- decode_format(format),
         {:ok, source_kind} <- decode_source_kind(Map.get(payload, "source_kind", "file")),
         {:ok, metadata} <- decode_issue_summary(Map.get(payload, "issue_summary")) do
      {:ok,
       %ImportPlan{
         format: format,
         parser_version: parser_version,
         source_kind: source_kind,
         data: data,
         metadata: metadata
       }}
    end
  end

  defp decode_plan(_payload), do: {:error, :invalid_import_plan}

  # No `"storyarn"` clause: the native format is gone, so a stored plan carrying
  # it decodes to `{:error, :invalid_import_plan}` and its attempt fails rather
  # than materializing through a format nothing can produce any more. Plans are
  # retained 24h and re-extended on enqueue, so an attempt prepared just before
  # the deploy could otherwise have drained through days later. Nothing in the
  # product could emit that file — the export side was hidden from the picker —
  # so the population is a hand-crafted or long-archived file, and a failed
  # import states that plainly.
  defp decode_format("yarn"), do: {:ok, :yarn}
  defp decode_format(_format), do: {:error, :invalid_import_plan}

  # Older callers could omit source_kind. Treat those plans as single-file
  # imports, matching decode_plan/1's backwards-compatible default.
  defp encode_source_kind(nil), do: {:ok, "file"}
  defp encode_source_kind(:file), do: {:ok, "file"}
  defp encode_source_kind(:archive), do: {:ok, "archive"}
  defp encode_source_kind(_source_kind), do: {:error, :invalid_import_plan}

  # Preserve decoder compatibility with the previous payload shape, while
  # requiring the surrounding envelope to be current and key-bound.
  defp decode_source_kind(nil), do: {:ok, :file}
  defp decode_source_kind(""), do: {:ok, :file}
  defp decode_source_kind("file"), do: {:ok, :file}
  defp decode_source_kind("archive"), do: {:ok, :archive}
  defp decode_source_kind(_source_kind), do: {:error, :invalid_import_plan}

  defp encode_issue_summary(metadata) when is_map(metadata) do
    with {:ok, warning_count} <- encode_non_negative_count(metadata, :warning_count),
         {:ok, error_count} <- encode_non_negative_count(metadata, :error_count),
         {:ok, issue_count} <- encode_non_negative_count(metadata, :issue_count),
         {:ok, counts_by_code} <-
           encode_issue_counts_by_code(Map.get(metadata, :issue_counts_by_code, %{})) do
      {:ok,
       %{
         "warning_count" => warning_count,
         "error_count" => error_count,
         "issue_count" => issue_count,
         "issues_truncated" => Map.get(metadata, :issues_truncated) == true,
         "counts_by_code" => counts_by_code
       }}
    end
  end

  defp encode_issue_summary(_metadata), do: {:error, :invalid_import_plan}

  defp encode_non_negative_count(metadata, key) do
    case Map.get(metadata, key, 0) do
      count when is_integer(count) and count >= 0 -> {:ok, count}
      _invalid -> {:error, :invalid_import_plan}
    end
  end

  defp encode_issue_counts_by_code(counts) when is_map(counts) and map_size(counts) <= 1_000 do
    Enum.reduce_while(counts, {:ok, %{}}, fn
      {code, count}, {:ok, encoded}
      when (is_atom(code) or is_binary(code)) and is_integer(count) and count > 0 ->
        code = to_string(code)

        if code != "" and String.length(code) <= 100 do
          {:cont, {:ok, Map.put(encoded, code, count)}}
        else
          {:halt, {:error, :invalid_import_plan}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_import_plan}}
    end)
  end

  defp encode_issue_counts_by_code(_counts), do: {:error, :invalid_import_plan}

  defp decode_issue_summary(nil), do: {:ok, %{}}

  defp decode_issue_summary(%{
         "warning_count" => warning_count,
         "error_count" => error_count,
         "issue_count" => issue_count,
         "issues_truncated" => issues_truncated,
         "counts_by_code" => counts_by_code
       })
       when is_integer(warning_count) and warning_count >= 0 and is_integer(error_count) and error_count >= 0 and
              is_integer(issue_count) and issue_count >= 0 and is_boolean(issues_truncated) do
    with {:ok, counts_by_code} <- decode_issue_counts_by_code(counts_by_code),
         true <- warning_count + error_count == issue_count,
         true <- Enum.sum(Map.values(counts_by_code)) == issue_count do
      {:ok,
       %{
         warning_count: warning_count,
         error_count: error_count,
         issue_count: issue_count,
         issues_truncated: issues_truncated,
         issue_counts_by_code: counts_by_code
       }}
    else
      _invalid -> {:error, :invalid_import_plan}
    end
  end

  defp decode_issue_summary(_summary), do: {:error, :invalid_import_plan}

  defp decode_issue_counts_by_code(counts) when is_map(counts) and map_size(counts) <= 1_000 do
    if Enum.all?(counts, fn {code, count} ->
         is_binary(code) and code != "" and String.length(code) <= 100 and
           is_integer(count) and count > 0
       end) do
      {:ok, counts}
    else
      {:error, :invalid_import_plan}
    end
  end

  defp decode_issue_counts_by_code(_counts), do: {:error, :invalid_import_plan}
end
