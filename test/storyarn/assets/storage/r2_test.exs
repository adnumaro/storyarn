defmodule Storyarn.Assets.Storage.R2Test do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage.R2

  setup do
    original_config = Application.get_env(:storyarn, :r2, [])

    Application.put_env(:storyarn, :r2,
      bucket: "private-bucket",
      endpoint_url: "https://t3.storage.dev",
      public_url: nil
    )

    on_exit(fn -> Application.put_env(:storyarn, :r2, original_config) end)
  end

  describe "key_from_url/1" do
    test "extracts a key from the S3 endpoint URL" do
      url = "https://t3.storage.dev/private-bucket/projects/1/assets/image%20one.png"

      assert R2.key_from_url(url) == {:ok, "projects/1/assets/image one.png"}
    end

    test "preserves unicode normalization and filename case" do
      key = "workspaces/writers/banner/Fantasía Oscura.jpg"
      url = "https://t3.storage.dev/private-bucket/#{key}"

      assert R2.key_from_url(url) == {:ok, key}
    end

    test "extracts a key from a configured public URL" do
      Application.put_env(:storyarn, :r2,
        bucket: "private-bucket",
        endpoint_url: "https://t3.storage.dev",
        public_url: "https://assets.example.com/content"
      )

      assert R2.key_from_url("https://assets.example.com/content/projects/1/image.png") ==
               {:ok, "projects/1/image.png"}
    end

    test "rejects URLs from another origin" do
      assert R2.key_from_url("https://attacker.example/private-bucket/projects/1/image.png") ==
               {:error, :invalid_url}
    end
  end
end
