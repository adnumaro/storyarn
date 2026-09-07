defmodule Storyarn.Ideation.Recovery.Capsule do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.Inventory
  alias Storyarn.Platform.Vault

  @max_bytes Inventory.max_bytes()
  @max_encoded_bytes div((@max_bytes + 1024) * 4, 3) + 4

  def seal(data) do
    with :ok <- Inventory.validate(data),
         json = Inventory.encode(data),
         true <- byte_size(json) <= @max_bytes,
         {:ok, encrypted} <- Vault.encrypt(json) do
      {:ok, %{"version" => 1, "ciphertext" => Base.encode64(encrypted)}}
    else
      _ -> {:error, :ideation_recovery_capture_failed}
    end
  end

  def open(%{"version" => 1, "ciphertext" => encoded} = capsule)
      when is_binary(encoded) and byte_size(encoded) <= @max_encoded_bytes and map_size(capsule) == 2 do
    with {:ok, encrypted} <- Base.decode64(encoded),
         {:ok, json} when is_binary(json) and byte_size(json) <= @max_bytes <- Vault.decrypt(encrypted),
         {:ok, data} <- Jason.decode(json),
         :ok <- Inventory.validate(data),
         :ok <- validate_content_keys(data) do
      {:ok, data}
    else
      _ -> {:error, :invalid_ideation_recovery}
    end
  rescue
    # Invalid ciphertext/key versions must neither leak payloads nor crash import.
    _ -> {:error, :invalid_ideation_recovery}
  end

  def open(_), do: {:error, :invalid_ideation_recovery}

  defp validate_content_keys(data) do
    for collection <- ["revisions", "edits"],
        row <- data["rows"][collection],
        field <- ["title", "body"],
        encoded = row[field],
        not is_nil(encoded),
        reduce: :ok do
      :ok ->
        with {:ok, encrypted} <- Base.decode64(encoded),
             {:ok, plaintext} when is_binary(plaintext) <- Vault.decrypt(encrypted) do
          :ok
        else
          _ -> {:error, :invalid_ideation_recovery}
        end

      error ->
        error
    end
  end
end
