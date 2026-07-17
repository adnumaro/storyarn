defmodule Storyarn.Assets.StorageHash do
  @moduledoc false

  @spec sha256_chunks(Enumerable.t()) :: {:ok, String.t()} | {:error, term()}
  def sha256_chunks(chunks) do
    chunks
    |> Enum.reduce_while({:ok, :crypto.hash_init(:sha256)}, fn
      {:ok, chunk}, {:ok, hash_state} when is_binary(chunk) ->
        {:cont, {:ok, :crypto.hash_update(hash_state, chunk)}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      _unexpected, _acc ->
        {:halt, {:error, :unexpected_blob_stream_chunk}}
    end)
    |> finalize_hash()
  end

  defp finalize_hash({:ok, hash_state}) do
    hash = hash_state |> :crypto.hash_final() |> Base.encode16(case: :lower)
    {:ok, hash}
  end

  defp finalize_hash({:error, _reason} = error), do: error
end
