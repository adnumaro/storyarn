defmodule Storyarn.Platform.ObjectStorage.HashingTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.ObjectStorage.Hashing, as: StorageHash

  test "hashes streamed chunks without buffering the complete object" do
    chunks = [{:ok, "story"}, {:ok, "arn"}]

    assert StorageHash.sha256_chunks(chunks) ==
             {:ok, :sha256 |> :crypto.hash("storyarn") |> Base.encode16(case: :lower)}
  end

  test "propagates stream errors and rejects malformed chunks" do
    assert StorageHash.sha256_chunks([{:ok, "prefix"}, {:error, :closed}]) ==
             {:error, :closed}

    assert StorageHash.sha256_chunks([{:ok, "prefix"}, "invalid"]) ==
             {:error, :unexpected_blob_stream_chunk}
  end
end
