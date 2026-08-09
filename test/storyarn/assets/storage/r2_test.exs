defmodule Storyarn.Assets.Storage.R2Test do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage.R2

  @copy_result """
  <?xml version="1.0" encoding="UTF-8"?>
  <CopyObjectResult>
    <ETag>"copy-etag"</ETag>
    <LastModified>2026-07-17T08:00:00.000Z</LastModified>
  </CopyObjectResult>
  """

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

  describe "list_prefix/2" do
    test "uses a bounded provider page and returns its continuation token" do
      prefix = "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.request_path == "/private-bucket/"
        assert conn.query_params["list-type"] == "2"
        assert conn.query_params["prefix"] == prefix
        assert conn.query_params["max-keys"] == "2"
        assert conn.query_params["encoding-type"] == "url"
        assert_signed_header_request(conn)

        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>true</IsTruncated>
            <Contents>
              <Key>#{prefix}manifest.json</Key>
              <ETag>"manifest-etag"</ETag>
              <Size>12</Size>
            </Contents>
            <NextContinuationToken>next-page</NextContinuationToken>
          </ListBucketResult>
          """
        )
      end)

      assert {:ok, %{objects: [object], cursor: "next-page"}} = R2.list_prefix(prefix, limit: 2)
      assert object == %{key: prefix <> "manifest.json", size: 12, identity: ~s("manifest-etag")}
    end

    test "rejects unsafe options before contacting the provider" do
      prefix = "projects/1/snapshots/"
      assert {:error, :invalid_prefix} = R2.list_prefix("projects/1/snapshots", [])
      assert {:error, :invalid_prefix} = R2.list_prefix(prefix <> "/", [])
      assert {:error, :invalid_limit} = R2.list_prefix(prefix, limit: 0)
      assert {:error, :invalid_cursor} = R2.list_prefix(prefix, cursor: "")
    end

    test "rejects an out-of-scope object returned by the provider" do
      prefix = "projects/1/snapshots/"

      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>false</IsTruncated>
            <Contents><Key>projects/2/assets/private.bin</Key><Size>12</Size></Contents>
          </ListBucketResult>
          """
        )
      end)

      assert {:error, :invalid_list_response} = R2.list_prefix(prefix, limit: 2)
    end

    test "keeps identity pages restricted to canonical keys" do
      prefix = "projects/"

      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>false</IsTruncated>
            <Contents><Key>projects/1/snapshots/object-sets/v1/ready//rogue</Key><ETag>"rogue"</ETag><Size>1</Size></Contents>
          </ListBucketResult>
          """
        )
      end)

      assert {:error, :invalid_list_response} = R2.list_prefix(prefix, limit: 2)
    end

    test "rejects incoherent truncation metadata and missing object identities" do
      prefix = "projects/1/snapshots/"

      invalid_pages = [
        """
        <IsTruncated>true</IsTruncated>
        <Contents><Key>#{prefix}one</Key><ETag>"one"</ETag><Size>1</Size></Contents>
        """,
        """
        <IsTruncated>false</IsTruncated>
        <NextContinuationToken>unexpected</NextContinuationToken>
        <Contents><Key>#{prefix}one</Key><ETag>"one"</ETag><Size>1</Size></Contents>
        """,
        """
        <Contents><Key>#{prefix}one</Key><ETag>"one"</ETag><Size>1</Size></Contents>
        """,
        """
        <IsTruncated>false</IsTruncated>
        <Contents><Key>#{prefix}one</Key><Size>1</Size></Contents>
        """
      ]

      for page <- invalid_pages do
        Req.Test.expect(__MODULE__, fn conn ->
          Plug.Conn.send_resp(
            conn,
            200,
            "<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">#{page}</ListBucketResult>"
          )
        end)

        assert {:error, :invalid_list_response} = R2.list_prefix(prefix, limit: 2)
      end
    end
  end

  describe "list_prefix_metadata/2" do
    test "returns non-canonical in-prefix keys without requiring object identities" do
      prefix = "projects/"
      key = "projects/1/snapshots/object-sets/v1/ready//rogue"
      encoded_key = "projects%2F1%2Fsnapshots%2Fobject-sets%2Fv1%2Fready%2F%2Frogue"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.request_path == "/private-bucket/"
        assert conn.query_params["list-type"] == "2"
        assert conn.query_params["prefix"] == prefix
        assert conn.query_params["max-keys"] == "2"
        assert conn.query_params["encoding-type"] == "url"
        assert conn.query_params["continuation-token"] == "current-page"
        assert_signed_header_request(conn)

        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>true</IsTruncated>
            <EncodingType>url</EncodingType>
            <Contents><Key>#{encoded_key}</Key><Size>1</Size></Contents>
            <NextContinuationToken>next-page</NextContinuationToken>
          </ListBucketResult>
          """
        )
      end)

      assert {:ok, %{objects: [%{key: ^key, size: 1}], cursor: "next-page"}} =
               R2.list_prefix_metadata(prefix, limit: 2, cursor: "current-page")
    end

    test "decodes URL-encoded control, percent, and Unicode key bytes" do
      prefix = "projects/"
      nul_key = prefix <> <<0>> <> "nul"
      control_key = prefix <> <<1>> <> "rogue"
      percent_key = prefix <> "literal%2F.txt"
      unicode_key = prefix <> "café.txt"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["encoding-type"] == "url"

        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <EncodingType>url</EncodingType>
            <IsTruncated>false</IsTruncated>
            <Contents><Key>projects%2F%00nul</Key><Size>0</Size></Contents>
            <Contents><Key>projects%2F%01rogue</Key><Size>1</Size></Contents>
            <Contents><Key>projects%2Fliteral%252F.txt</Key><Size>2</Size></Contents>
            <Contents><Key>projects%2Fcaf%C3%A9.txt</Key><Size>3</Size></Contents>
          </ListBucketResult>
          """
        )
      end)

      assert {:ok, %{objects: objects, cursor: nil}} = R2.list_prefix_metadata(prefix, [])

      assert objects == [
               %{key: nul_key, size: 0},
               %{key: control_key, size: 1},
               %{key: percent_key, size: 2},
               %{key: unicode_key, size: 3}
             ]
    end

    test "rejects malformed URL encoding in provider keys" do
      for encoded_key <- ["projects%2Fbad%ZZ", "projects%2Fbad%FF"] do
        Req.Test.expect(__MODULE__, fn conn ->
          Plug.Conn.send_resp(
            conn,
            200,
            """
            <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
              <EncodingType>url</EncodingType>
              <IsTruncated>false</IsTruncated>
              <Contents><Key>#{encoded_key}</Key><Size>1</Size></Contents>
            </ListBucketResult>
            """
          )
        end)

        assert {:error, :invalid_list_response} = R2.list_prefix_metadata("projects/", [])
      end
    end

    test "rejects objects outside the requested prefix" do
      prefix = "projects/1/snapshots/"

      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>false</IsTruncated>
            <Contents><Key>projects/2/snapshots/object-sets/v1/ready//rogue</Key><Size>1</Size></Contents>
          </ListBucketResult>
          """
        )
      end)

      assert {:error, :invalid_list_response} = R2.list_prefix_metadata(prefix, limit: 2)
    end
  end

  describe "delete_if_matches/2" do
    test "deletes atomically only when the ETag still matches" do
      key = "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/manifest.json"

      Req.Test.expect(__MODULE__, fn conn ->
        assert_signed_header_request(conn)
        assert_signed_header(conn, "if-match")
        assert conn.method == "DELETE"
        assert Plug.Conn.get_req_header(conn, "if-match") == [~s("manifest-etag")]
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert :ok = R2.delete_if_matches(key, ~s("manifest-etag"))
    end

    test "preserves an object whose ETag changed" do
      key = "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/manifest.json"

      Req.Test.expect(__MODULE__, fn conn ->
        assert_signed_header(conn, "if-match")
        assert conn.method == "DELETE"
        assert Plug.Conn.get_req_header(conn, "if-match") == [~s("old-etag")]
        Plug.Conn.send_resp(conn, 412, "")
      end)

      assert {:error, :object_changed} = R2.delete_if_matches(key, ~s("old-etag"))
    end

    test "treats an already absent object as deleted" do
      key = "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/manifest.json"

      Req.Test.expect(__MODULE__, fn conn ->
        assert_signed_header(conn, "if-match")
        assert conn.method == "DELETE"
        assert Plug.Conn.get_req_header(conn, "if-match") == [~s("manifest-etag")]
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert :ok = R2.delete_if_matches(key, ~s("manifest-etag"))
    end
  end

  describe "namespace_fingerprint/0" do
    test "binds the endpoint and bucket without exposing credentials" do
      assert {:ok, original} = R2.namespace_fingerprint()
      assert original =~ ~r/\A[0-9a-f]{64}\z/

      Application.put_env(:storyarn, :r2,
        bucket: "another-private-bucket",
        endpoint_url: "https://t3.storage.dev",
        public_url: nil
      )

      assert {:ok, changed} = R2.namespace_fingerprint()
      refute changed == original
      refute changed =~ "test-secret-key"
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

  describe "upload_stream/3" do
    test "aborts an initialized multipart upload when a part fails" do
      key = "projects/1/snapshots/object-sets/v1/staging/AbCdEfGhIjKlMnOp/blobs/hash.png"

      Req.Test.expect(__MODULE__, 3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.method do
          "POST" ->
            assert conn.query_params == %{"uploads" => "1"}

            Plug.Conn.send_resp(
              conn,
              200,
              """
              <InitiateMultipartUploadResult>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <UploadId>upload-123</UploadId>
              </InitiateMultipartUploadResult>
              """
            )

          "PUT" ->
            assert conn.query_params["uploadId"] == "upload-123"
            assert conn.query_params["partNumber"] == "1"
            Plug.Conn.send_resp(conn, 400, "<Error><Code>InvalidPart</Code></Error>")

          "DELETE" ->
            assert conn.query_params == %{"uploadId" => "upload-123"}
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert {:error, {:http_error, 400, _response}} =
               R2.upload_stream(key, [{:ok, "bounded chunk"}], "image/png")
    end
  end

  describe "copy_if_absent/2" do
    test "uses a server-side destination-conditional copy" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/private-bucket/projects/2/blobs/hash.png"
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]

        assert Plug.Conn.get_req_header(conn, "x-amz-copy-source") == [
                 "/private-bucket/projects/1/blobs/hash.png"
               ]

        assert Plug.Conn.get_req_header(conn, "cf-copy-destination-if-none-match") == []
        assert_signed_header_request(conn)
        Plug.Conn.send_resp(conn, 200, @copy_result)
      end)

      assert {:ok, true} =
               R2.copy_if_absent(
                 "projects/1/blobs/hash.png",
                 "projects/2/blobs/hash.png"
               )
    end

    test "treats a failed destination precondition as an existing object" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
        Plug.Conn.send_resp(conn, 412, "<Error><Code>PreconditionFailed</Code></Error>")
      end)

      assert {:ok, false} =
               R2.copy_if_absent(
                 "projects/1/blobs/hash.png",
                 "projects/2/blobs/hash.png"
               )
    end

    test "retries a conditional request conflict without claiming ownership" do
      {:ok, requests} = Agent.start_link(fn -> 0 end)

      Req.Test.expect(__MODULE__, 2, fn conn ->
        request_number = Agent.get_and_update(requests, &{&1 + 1, &1 + 1})

        case request_number do
          1 -> Plug.Conn.send_resp(conn, 409, "<Error><Code>ConditionalRequestConflict</Code></Error>")
          2 -> Plug.Conn.send_resp(conn, 412, "<Error><Code>PreconditionFailed</Code></Error>")
        end
      end)

      assert {:ok, false} =
               R2.copy_if_absent(
                 "projects/1/blobs/hash.png",
                 "projects/2/blobs/hash.png"
               )

      assert Agent.get(requests, & &1) == 2
    end

    test "rejects an embedded CopyObject error returned with HTTP 200" do
      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, "<Error><Code>InternalError</Code></Error>")
      end)

      assert {:error, :copy_object_error_response} =
               R2.copy_if_absent(
                 "projects/1/blobs/hash.png",
                 "projects/2/blobs/hash.png"
               )
    end

    test "adds Cloudflare's destination condition only for an R2 endpoint" do
      Application.put_env(:storyarn, :r2,
        bucket: "private-bucket",
        endpoint_url: "https://account.r2.cloudflarestorage.com",
        public_url: nil
      )

      Application.put_env(:ex_aws, :s3,
        host: "account.r2.cloudflarestorage.com",
        scheme: "https://",
        region: "auto"
      )

      Req.Test.expect(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]
        assert Plug.Conn.get_req_header(conn, "cf-copy-destination-if-none-match") == ["*"]

        [authorization] = Plug.Conn.get_req_header(conn, "authorization")
        assert authorization =~ "cf-copy-destination-if-none-match"
        Plug.Conn.send_resp(conn, 200, @copy_result)
      end)

      assert {:ok, true} =
               R2.copy_if_absent(
                 "projects/1/blobs/hash.png",
                 "projects/2/blobs/hash.png"
               )
    end
  end

  describe "copy/2" do
    test "validates the CopyObject result body" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"
        Plug.Conn.send_resp(conn, 200, @copy_result)
      end)

      assert :ok =
               R2.copy(
                 "projects/1/blobs/hash.png",
                 "projects/1/assets/copy/hash.png"
               )
    end

    test "rejects an embedded CopyObject error returned with HTTP 200" do
      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, "<Error><Code>InternalError</Code></Error>")
      end)

      assert {:error, :copy_object_error_response} =
               R2.copy(
                 "projects/1/blobs/hash.png",
                 "projects/1/assets/copy/hash.png"
               )
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

  defp assert_signed_header(conn, expected_header) do
    [authorization] = Plug.Conn.get_req_header(conn, "authorization")
    [signed_headers] = Regex.run(~r/SignedHeaders=([^,\s]+)/, authorization, capture: :all_but_first)

    assert expected_header in String.split(signed_headers, ";")
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
