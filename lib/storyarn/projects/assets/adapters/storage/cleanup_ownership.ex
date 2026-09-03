defmodule Storyarn.Projects.Assets.StorageCleanupOwnership do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Assets.StorageCleanupOwnershipReceipt
  alias Storyarn.Repo

  @force_delete_prefix "__storyarn_force_delete__:"

  @spec storage_keys(pos_integer()) :: {:ok, [String.t()]} | :error
  def storage_keys(cleanup_request_id) when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    case Repo.get(StorageCleanupOwnershipReceipt, cleanup_request_id) do
      %StorageCleanupOwnershipReceipt{storage_keys: storage_keys} when is_list(storage_keys) ->
        {:ok, storage_keys}

      _receipt ->
        :error
    end
  end

  def storage_keys(_cleanup_request_id), do: :error

  @spec handed_off_for_prefix?(String.t()) :: boolean()
  def handed_off_for_prefix?(prefix) when is_binary(prefix) do
    Repo.exists?(
      from(namespace in "storage_cleanup_ownership_namespaces",
        where: field(namespace, :object_prefix) == ^prefix
      )
    )
  end

  def handed_off_for_prefix?(_prefix), do: false

  @spec handed_off_for_key?(String.t()) :: boolean()
  def handed_off_for_key?(storage_key) when is_binary(storage_key), do: handed_off_for_any_key?([storage_key])

  def handed_off_for_key?(_storage_key), do: false

  @spec handed_off_for_any_key?([String.t()]) :: boolean()
  def handed_off_for_any_key?(storage_keys) when is_list(storage_keys) do
    targets = cleanup_targets(storage_keys)

    targets != [] and
      Repo.exists?(
        from(request in "storage_cleanup_requests",
          where: fragment("? && ?::text[]", field(request, :storage_keys), ^targets)
        )
      )
  end

  def handed_off_for_any_key?(_storage_keys), do: false

  defp cleanup_targets(storage_keys) do
    storage_keys
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.flat_map(&[&1, @force_delete_prefix <> &1])
    |> Enum.uniq()
  end
end
