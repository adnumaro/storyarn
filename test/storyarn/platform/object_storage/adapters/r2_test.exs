defmodule Storyarn.Platform.ObjectStorage.Adapters.R2Test do
  use ExUnit.Case, async: false

  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.ObjectStorage.Adapters.R2

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

  test "presigns direct PUT with the browser-safe signed content type and requested expiry" do
    key = "workspace-snapshot-imports/v1/1/#{Ecto.UUID.generate()}/snapshot.zip"

    assert {:ok, url, %{headers: %{"content-type" => "application/zip"}}} =
             R2.presigned_upload_url(key, "application/zip", expires_in: 3600, content_length: 123)

    query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["X-Amz-Expires"] == "3600"
    assert "content-length" in String.split(query["X-Amz-SignedHeaders"], ";")
    assert "content-type" in String.split(query["X-Amz-SignedHeaders"], ";")
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
      prefix = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/"

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
            <Contents><Key>projects/1/snapshots/archives/v2/ready//rogue</Key><ETag>"rogue"</ETag><Size>1</Size></Contents>
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
      key = "projects/1/snapshots/archives/v2/ready//rogue"
      encoded_key = "projects%2F1%2Fsnapshots%2Farchives%2Fv2%2Fready%2F%2Frogue"

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
            <Contents><Key>projects/2/snapshots/archives/v2/ready//rogue</Key><Size>1</Size></Contents>
          </ListBucketResult>
          """
        )
      end)

      assert {:error, :invalid_list_response} = R2.list_prefix_metadata(prefix, limit: 2)
    end
  end

  describe "delete_if_matches/2" do
    test "deletes atomically only when the ETag still matches" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/manifest.json"

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
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/manifest.json"

      Req.Test.expect(__MODULE__, fn conn ->
        assert_signed_header(conn, "if-match")
        assert conn.method == "DELETE"
        assert Plug.Conn.get_req_header(conn, "if-match") == [~s("old-etag")]
        Plug.Conn.send_resp(conn, 412, "")
      end)

      assert {:error, :object_changed} = R2.delete_if_matches(key, ~s("old-etag"))
    end

    test "treats an already absent object as deleted" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/manifest.json"

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
    test "matches fingerprints persisted before the adapter module moved under Projects" do
      legacy_fingerprint =
        namespace_fingerprint([
          "Elixir.Storyarn.Assets.Storage.R2",
          "https://t3.storage.dev",
          "private-bucket",
          "t3.storage.dev",
          "https://",
          nil
        ])

      assert R2.namespace_fingerprint() == {:ok, legacy_fingerprint}
    end

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

  defp namespace_fingerprint(parts) do
    parts
    |> Jason.encode_to_iodata!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
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
    test "accepts an exact successful multipart completion response" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      expected_url = "https://t3.storage.dev/private-bucket/#{key}"

      Req.Test.expect(__MODULE__, 3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          conn.method == "POST" and conn.query_params == %{"uploads" => "1"} ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <InitiateMultipartUploadResult>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <UploadId>upload-success</UploadId>
              </InitiateMultipartUploadResult>
              """
            )

          conn.method == "PUT" ->
            assert conn.query_params == %{
                     "partNumber" => "1",
                     "uploadId" => "upload-success"
                   }

            conn
            |> Plug.Conn.put_resp_header("etag", ~s("part-etag"))
            |> Plug.Conn.send_resp(200, "")

          conn.method == "POST" ->
            assert conn.query_params == %{"uploadId" => "upload-success"}

            Plug.Conn.send_resp(
              conn,
              200,
              """
              <CompleteMultipartUploadResult>
                <Location>https://t3.storage.dev/private-bucket/#{key}</Location>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <ETag>"archive-etag"</ETag>
              </CompleteMultipartUploadResult>
              """
            )
        end
      end)

      assert {:ok, ^expected_url} =
               R2.upload_stream(key, [{:ok, "bounded archive chunk"}], "application/zip")
    end

    test "aborts an initialized multipart upload when a part fails" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

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

    test "hard-stops a hung UploadPart at the configured wall-clock deadline and aborts its upload id" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      original_policy = Application.get_env(:storyarn, ObjectStorage)
      Application.put_env(:storyarn, ObjectStorage, multipart_upload_part_deadline_ms: 50)
      on_exit(fn -> restore_env(:storyarn, ObjectStorage, original_policy) end)

      Req.Test.expect(__MODULE__, 3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          conn.method == "POST" ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <InitiateMultipartUploadResult>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <UploadId>upload-timeout</UploadId>
              </InitiateMultipartUploadResult>
              """
            )

          conn.method == "PUT" ->
            assert conn.query_params == %{"partNumber" => "1", "uploadId" => "upload-timeout"}
            Process.sleep(1_000)
            Plug.Conn.send_resp(conn, 200, "")

          conn.method == "DELETE" ->
            assert conn.query_params == %{"uploadId" => "upload-timeout"}
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      started_at = System.monotonic_time(:millisecond)

      assert {:error, :multipart_upload_part_timeout} =
               R2.upload_stream(key, [{:ok, "bounded chunk"}], "application/zip")

      assert System.monotonic_time(:millisecond) - started_at < 800
    end

    test "turns UploadPart task raises and exits into normal failures before aborting" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      for failure <- [:raise, :exit] do
        upload_id = "upload-#{failure}"

        Req.Test.expect(__MODULE__, 3, fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)

          cond do
            conn.method == "POST" ->
              Plug.Conn.send_resp(
                conn,
                200,
                """
                <InitiateMultipartUploadResult>
                  <Bucket>private-bucket</Bucket>
                  <Key>#{key}</Key>
                  <UploadId>#{upload_id}</UploadId>
                </InitiateMultipartUploadResult>
                """
              )

            conn.method == "PUT" and failure == :raise ->
              raise "simulated UploadPart failure"

            conn.method == "PUT" ->
              exit(:simulated_upload_part_exit)

            conn.method == "DELETE" ->
              assert conn.query_params == %{"uploadId" => upload_id}
              Plug.Conn.send_resp(conn, 204, "")
          end
        end)

        assert {:error, :multipart_upload_part_task_exit} =
                 R2.upload_stream(key, [{:ok, "bounded chunk"}], "application/zip")
      end
    end

    test "kills the linked UploadPart task when its upload owner dies" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      test_process = self()

      Req.Test.stub(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          conn.method == "POST" ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <InitiateMultipartUploadResult>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <UploadId>upload-owner-died</UploadId>
              </InitiateMultipartUploadResult>
              """
            )

          conn.method == "PUT" ->
            send(test_process, {:upload_part_child, self()})
            receive do: (:never -> Plug.Conn.send_resp(conn, 200, ""))

          true ->
            send(test_process, {:unexpected_provider_request, conn.method})
            Plug.Conn.send_resp(conn, 500, "")
        end
      end)

      owner =
        spawn(fn ->
          receive do
            :start ->
              result = R2.upload_stream(key, [{:ok, "bounded chunk"}], "application/zip")
              send(test_process, {:unexpected_upload_result, result})
          end
        end)

      Req.Test.allow(__MODULE__, self(), owner)
      send(owner, :start)

      assert_receive {:upload_part_child, child}, 1_000
      child_monitor = Process.monitor(child)
      Process.exit(owner, :kill)

      assert_receive {:DOWN, ^child_monitor, :process, ^child, _reason}, 1_000
      refute_receive {:unexpected_upload_result, _result}
      refute_receive {:unexpected_provider_request, _method}
    end

    test "aborts when multipart completion returns an embedded error with HTTP 200" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      Req.Test.expect(__MODULE__, 4, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          conn.method == "POST" and conn.query_params == %{"uploads" => "1"} ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <InitiateMultipartUploadResult>
                <Bucket>private-bucket</Bucket>
                <Key>#{key}</Key>
                <UploadId>upload-embedded-error</UploadId>
              </InitiateMultipartUploadResult>
              """
            )

          conn.method == "PUT" ->
            assert conn.query_params == %{
                     "partNumber" => "1",
                     "uploadId" => "upload-embedded-error"
                   }

            conn
            |> Plug.Conn.put_resp_header("etag", ~s("part-etag"))
            |> Plug.Conn.send_resp(200, "")

          conn.method == "POST" ->
            assert conn.query_params == %{"uploadId" => "upload-embedded-error"}

            Plug.Conn.send_resp(
              conn,
              200,
              "<Error><Code>InternalError</Code><Message>completion failed</Message></Error>"
            )

          conn.method == "DELETE" ->
            assert conn.query_params == %{"uploadId" => "upload-embedded-error"}
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert {:error, :invalid_multipart_upload_completion_response} =
               R2.upload_stream(key, [{:ok, "bounded archive chunk"}], "application/zip")
    end
  end

  describe "abort_incomplete_multipart_uploads/2" do
    test "inventories every exact v2 archive key that stream fallback may write" do
      keys =
        for state <- ["staging", "ready"], filename <- ["snapshot.zip", "manifest.json"] do
          "projects/1/snapshots/archives/v2/#{state}/AbCdEfGhIjKlMnOp/#{filename}"
        end

      Req.Test.expect(__MODULE__, length(keys), fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.query_params["prefix"] in keys

        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>false</IsTruncated>
          </ListMultipartUploadsResult>
          """
        )
      end)

      for key <- keys do
        assert {:ok, 0} = R2.abort_incomplete_multipart_uploads(key, [])
      end
    end

    test "inventories an exact restore-reservation blob key for durable cleanup" do
      key =
        "projects/42/storage-reservations/v1/restore-staging/" <>
          "3abf435a-c086-4801-9b91-5a49a440f917/blobs/#{String.duplicate("a", 64)}.png"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.query_params["uploads"] == "1"
        assert conn.query_params["prefix"] == key

        Plug.Conn.send_resp(
          conn,
          200,
          """
          <ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <IsTruncated>false</IsTruncated>
          </ListMultipartUploadsResult>
          """
        )
      end)

      assert {:ok, 0} = R2.abort_incomplete_multipart_uploads(key, [])
    end

    test "paginates exact-key uploads and aborts every durable cleanup target" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
      {:ok, request_count} = Agent.start_link(fn -> 0 end)

      Req.Test.expect(__MODULE__, 7, fn conn ->
        request_number = Agent.get_and_update(request_count, &{&1 + 1, &1 + 1})
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          request_number == 1 and conn.method == "GET" ->
            assert conn.query_params["uploads"] == "1"
            assert conn.query_params["prefix"] == key
            assert conn.query_params["max-uploads"] == "100"

            Plug.Conn.send_resp(
              conn,
              200,
              multipart_upload_page(key, "upload-1", true, key, "upload-1")
            )

          request_number == 2 and conn.method == "GET" ->
            assert conn.query_params["key-marker"] == key
            assert conn.query_params["upload-id-marker"] == "upload-1"

            Plug.Conn.send_resp(
              conn,
              200,
              multipart_upload_page(key, "upload-2", false, nil, nil)
            )

          request_number in [4, 6] and conn.method == "GET" ->
            assert conn.query_params["uploadId"] in ["upload-1", "upload-2"]
            assert conn.query_params["max_parts"] == "1"
            Plug.Conn.send_resp(conn, 200, multipart_parts_page([]))

          request_number == 7 and conn.method == "GET" ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                <IsTruncated>false</IsTruncated>
              </ListMultipartUploadsResult>
              """
            )

          request_number in [3, 5] and conn.method == "DELETE" ->
            assert conn.query_params["uploadId"] in ["upload-1", "upload-2"]
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert {:ok, 2} = R2.abort_incomplete_multipart_uploads(key, [])
    end

    test "repeats abort and inventory until an in-flight part no longer recreates the upload" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/snapshot.zip"
      {:ok, request_count} = Agent.start_link(fn -> 0 end)

      Req.Test.expect(__MODULE__, 6, fn conn ->
        request_number = Agent.get_and_update(request_count, &{&1 + 1, &1 + 1})
        conn = Plug.Conn.fetch_query_params(conn)

        case {request_number, conn.method} do
          {1, "GET"} ->
            Plug.Conn.send_resp(
              conn,
              200,
              multipart_upload_page(key, "upload-in-flight", false, nil, nil)
            )

          {number, "DELETE"} when number in [2, 4] ->
            assert conn.query_params["uploadId"] == "upload-in-flight"
            Plug.Conn.send_resp(conn, 204, "")

          {3, "GET"} ->
            assert conn.query_params["uploadId"] == "upload-in-flight"
            Plug.Conn.send_resp(conn, 200, multipart_parts_page([1]))

          {5, "GET"} ->
            assert conn.query_params["uploadId"] == "upload-in-flight"
            Plug.Conn.send_resp(conn, 200, multipart_parts_page([]))

          {6, "GET"} ->
            Plug.Conn.send_resp(
              conn,
              200,
              """
              <ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                <IsTruncated>false</IsTruncated>
              </ListMultipartUploadsResult>
              """
            )
        end
      end)

      assert {:ok, 1} = R2.abort_incomplete_multipart_uploads(key, [])
    end

    test "fails closed while an aborted upload remains visible after the bounded passes" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/manifest.json"

      Req.Test.expect(__MODULE__, 3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        cond do
          conn.method == "GET" and conn.query_params["uploads"] == "1" ->
            Plug.Conn.send_resp(conn, 200, multipart_upload_page(key, "upload-still-visible", false, nil, nil))

          conn.method == "GET" ->
            assert conn.query_params["uploadId"] == "upload-still-visible"
            Plug.Conn.send_resp(conn, 200, multipart_parts_page([1]))

          conn.method == "DELETE" ->
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      assert {:error, :multipart_cleanup_not_quiescent} =
               R2.abort_incomplete_multipart_uploads(key, max_passes: 1)
    end

    test "fails closed when the bounded inventory cannot be exhausted" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.query_params["max-uploads"] == "1"

        Plug.Conn.send_resp(
          conn,
          200,
          multipart_upload_page(key, "upload-1", true, key, "upload-1")
        )
      end)

      assert {:error, :multipart_cleanup_inventory_limit_exceeded} =
               R2.abort_incomplete_multipart_uploads(key, max_uploads: 1)
    end

    test "keeps cleanup pending when an abort fails" do
      key = "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"

      Req.Test.expect(__MODULE__, 2, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.method do
          "GET" ->
            Plug.Conn.send_resp(
              conn,
              200,
              multipart_upload_page(key, "upload-1", false, nil, nil)
            )

          "DELETE" ->
            assert conn.query_params["uploadId"] == "upload-1"
            Plug.Conn.send_resp(conn, 400, "abort rejected")
        end
      end)

      assert {:error, {:multipart_cleanup_abort_failed, {:http_error, 400, _response}}} =
               R2.abort_incomplete_multipart_uploads(key, [])
    end
  end

  describe "incomplete_multipart_upload_count/2" do
    test "returns exact read-only provider inventory without aborting uploads" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/snapshot.zip"

      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.method == "GET"
        assert conn.query_params["prefix"] == key
        Plug.Conn.send_resp(conn, 200, multipart_upload_page(key, "upload-1", false, nil, nil))
      end)

      assert {:ok, 1} = R2.incomplete_multipart_upload_count(key, [])
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

  describe "presigned_download_url/3" do
    test "signs a bounded GET with private attachment response metadata" do
      key = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/snapshot.zip"

      assert {:ok, url} =
               R2.presigned_download_url(key, "application/zip",
                 expires_in: 300,
                 filename: "veilbreak-snapshot-v3.zip"
               )

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.scheme == "https"
      assert uri.host == "t3.storage.dev"
      assert uri.path == "/private-bucket/#{key}"
      assert query["X-Amz-Expires"] == "300"
      assert query["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256"
      assert is_binary(query["X-Amz-Signature"])
      assert query["response-cache-control"] == "private, no-store, no-transform"
      assert query["response-content-type"] == "application/zip"

      assert query["response-content-disposition"] ==
               ~s(attachment; filename="veilbreak-snapshot-v3.zip")
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

  defp multipart_upload_page(key, upload_id, truncated?, next_key_marker, next_upload_id_marker) do
    next_markers =
      if truncated? do
        """
        <NextKeyMarker>#{next_key_marker}</NextKeyMarker>
        <NextUploadIdMarker>#{next_upload_id_marker}</NextUploadIdMarker>
        """
      else
        ""
      end

    """
    <ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <IsTruncated>#{truncated?}</IsTruncated>
      #{next_markers}
      <Upload>
        <Key>#{key}</Key>
        <UploadId>#{upload_id}</UploadId>
      </Upload>
    </ListMultipartUploadsResult>
    """
  end

  defp multipart_parts_page(part_numbers) do
    parts =
      Enum.map_join(part_numbers, "\n", fn part_number ->
        """
        <Part>
          <PartNumber>#{part_number}</PartNumber>
          <ETag>"part-#{part_number}"</ETag>
          <Size>1</Size>
        </Part>
        """
      end)

    """
    <ListPartsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      #{parts}
    </ListPartsResult>
    """
  end

  defp assert_signed_header(conn, expected_header) do
    [authorization] = Plug.Conn.get_req_header(conn, "authorization")
    [signed_headers] = Regex.run(~r/SignedHeaders=([^,\s]+)/, authorization, capture: :all_but_first)

    assert expected_header in String.split(signed_headers, ";")
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
