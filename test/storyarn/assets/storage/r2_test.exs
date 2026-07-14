defmodule Storyarn.Assets.Storage.R2Test do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage.R2

  setup do
    original_config = Application.get_env(:storyarn, :r2, [])
    original_s3_config = Application.get_env(:ex_aws, :s3)
    original_access_key_id = Application.get_env(:ex_aws, :access_key_id)
    original_secret_access_key = Application.get_env(:ex_aws, :secret_access_key)
    original_req_opts = Application.get_env(:ex_aws, :req_opts)

    Application.put_env(:storyarn, :r2,
      bucket: "private-bucket",
      endpoint_url: "https://t3.storage.dev",
      public_url: nil
    )

    Application.put_env(:ex_aws, :s3,
      host: "t3.storage.dev",
      scheme: "https://",
      region: "auto"
    )

    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")
    Application.put_env(:ex_aws, :req_opts, plug: {Req.Test, __MODULE__})

    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:storyarn, :r2, original_config)
      restore_env(:ex_aws, :s3, original_s3_config)
      restore_env(:ex_aws, :access_key_id, original_access_key_id)
      restore_env(:ex_aws, :secret_access_key, original_secret_access_key)
      restore_env(:ex_aws, :req_opts, original_req_opts)
    end)
  end

  describe "stat/1" do
    test "reads object metadata through a signed HEAD request" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "HEAD"
        assert conn.request_path == "/private-bucket/projects/1/assets/image.png"
        assert conn.query_string == ""
        assert_signed_header_request(conn)

        conn
        |> Plug.Conn.put_resp_header("content-length", "12")
        |> Plug.Conn.put_resp_header("content-type", "image/png")
        |> Plug.Conn.put_resp_header("etag", ~s("asset-etag"))
        |> Plug.Conn.send_resp(200, "")
      end)

      assert R2.stat("projects/1/assets/image.png") ==
               {:ok, %{size: 12, content_type: "image/png", etag: ~s("asset-etag")}}
    end
  end

  describe "put_if_absent/3" do
    test "uses a conditional PUT and reports creation ownership" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, "https://t3.storage.dev/private-bucket/projects/1/blobs/hash.png", true} =
               R2.put_if_absent("projects/1/blobs/hash.png", "content", "image/png")
    end

    test "treats a failed precondition as an existing object" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
        Plug.Conn.send_resp(conn, 412, "")
      end)

      assert {:ok, "https://t3.storage.dev/private-bucket/projects/1/blobs/hash.png", false} =
               R2.put_if_absent("projects/1/blobs/hash.png", "content", "image/png")
    end

    test "surfaces a conflict instead of claiming the object exists" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
        Plug.Conn.send_resp(conn, 409, "conflict")
      end)

      assert {:error, {:http_error, 409, _response}} =
               R2.put_if_absent("projects/1/blobs/hash.png", "content", "image/png")
    end
  end

  describe "stream/4" do
    test "downloads a signed byte range without exposing presigned query parameters" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/private-bucket/projects/1/assets/image.png"
        assert conn.query_string == ""
        assert Plug.Conn.get_req_header(conn, "range") == ["bytes=2-6"]
        assert Plug.Conn.get_req_header(conn, "if-match") == [~s("asset-etag")]
        assert_signed_header_request(conn)

        Plug.Conn.send_resp(conn, 206, "23456")
      end)

      assert {:ok, stream} =
               R2.stream("projects/1/assets/image.png", 2, 5, etag: ~s("asset-etag"))

      assert Enum.to_list(stream) == [{:ok, "23456"}]
    end
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

  defp assert_signed_header_request(conn) do
    [authorization] = Plug.Conn.get_req_header(conn, "authorization")

    assert String.starts_with?(
             authorization,
             "AWS4-HMAC-SHA256 Credential=test-access-key/"
           )

    assert Plug.Conn.get_req_header(conn, "x-amz-date") != []
    refute authorization =~ "X-Amz-Signature"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
