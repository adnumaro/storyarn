defmodule Storyarn.Imports.PlanStorage do
  @moduledoc """
  Stores import plans compressed and encrypted in private object storage.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Vault

  @spec storage_key(pos_integer()) :: String.t()
  def storage_key(project_id) when is_integer(project_id) and project_id > 0 do
    "imports/plans/#{Ecto.UUID.generate()}.plan.enc"
  end

  @spec store(pos_integer(), ImportPlan.t()) :: {:ok, String.t()} | {:error, atom()}
  def store(project_id, %ImportPlan{} = plan) do
    project_id
    |> storage_key()
    |> store_at(plan)
  end

  @spec store_at(String.t(), ImportPlan.t()) :: {:ok, String.t()} | {:error, atom()}
  def store_at(key, %ImportPlan{} = plan) when is_binary(key) do
    if ImportPlan.error?(plan) do
      {:error, :import_plan_has_errors}
    else
      payload = %{
        "format" => to_string(plan.format),
        "parser_version" => plan.parser_version,
        "source_kind" => to_string(plan.source_kind),
        "data" => plan.data
      }

      with {:ok, json} <- Jason.encode(payload),
           compressed = :zlib.gzip(json),
           {:ok, encrypted} <- Vault.encrypt(compressed),
           {:ok, _private_url} <- Storage.upload(key, encrypted, "application/octet-stream") do
        {:ok, key}
      else
        _error -> {:error, :import_plan_storage_failed}
      end
    end
  end

  @spec load(String.t()) :: {:ok, ImportPlan.t()} | {:error, atom()}
  def load(key) when is_binary(key) do
    with {:ok, encrypted} <- Storage.download(key),
         {:ok, compressed} <- Vault.decrypt(encrypted),
         {:ok, json} <- gunzip(compressed),
         {:ok, payload} when is_map(payload) <- Jason.decode(json),
         {:ok, plan} <- decode_plan(payload) do
      {:ok, plan}
    else
      _error -> {:error, :import_plan_unavailable}
    end
  end

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key), do: Storage.delete(key)

  defp gunzip(compressed) do
    {:ok, :zlib.gunzip(compressed)}
  rescue
    ErlangError -> {:error, :invalid_import_plan}
  end

  defp decode_plan(%{"format" => format, "parser_version" => parser_version, "data" => data} = payload)
       when is_binary(parser_version) and is_map(data) do
    with {:ok, format} <- decode_format(format),
         {:ok, source_kind} <- decode_source_kind(Map.get(payload, "source_kind", "file")) do
      {:ok,
       %ImportPlan{
         format: format,
         parser_version: parser_version,
         source_kind: source_kind,
         data: data
       }}
    end
  end

  defp decode_plan(_payload), do: {:error, :invalid_import_plan}

  defp decode_format("storyarn"), do: {:ok, :storyarn}
  defp decode_format("yarn"), do: {:ok, :yarn}
  defp decode_format(_format), do: {:error, :invalid_import_plan}

  defp decode_source_kind("file"), do: {:ok, :file}
  defp decode_source_kind("archive"), do: {:ok, :archive}
  defp decode_source_kind(_source_kind), do: {:error, :invalid_import_plan}
end
