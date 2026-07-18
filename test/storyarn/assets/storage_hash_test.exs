defmodule Storyarn.Assets.StorageHashTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.StorageHash

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
