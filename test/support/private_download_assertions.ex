defmodule StoryarnWeb.PrivateDownloadAssertions do
  @moduledoc false

  import ExUnit.Assertions
  import Plug.Conn, only: [get_resp_header: 2]

  def assert_direct_private_response(conn, body) do
    assert get_resp_header(conn, "location") == []
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-length") == [Integer.to_string(byte_size(body))]
    assert_no_external_storage_response(conn)
  end

  def assert_no_external_storage_response(conn) do
    response = conn |> then(&inspect({&1.resp_headers, &1.resp_body})) |> String.downcase()

    refute response =~ "storage.dev"
    refute response =~ "x-amz-"
  end
end
