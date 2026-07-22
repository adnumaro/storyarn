defmodule StoryarnWeb.PrivateDownloadTest do
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]

  alias StoryarnWeb.PrivateDownload

  test "halts a partially-sent response when the storage stream fails" do
    previous_storage = Application.get_env(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, adapter: Storyarn.FailingStreamStorage)

    on_exit(fn ->
      if previous_storage do
        Application.put_env(:storyarn, :storage, previous_storage)
      else
        Application.delete_env(:storyarn, :storage)
      end
    end)

    conn = Plug.Test.conn(:get, "/private-download")

    assert {:ok, streamed_conn} = PrivateDownload.send(conn, "projects/1/private.bin", [])
    assert streamed_conn.halted
    assert streamed_conn.state == :chunked
    assert get_resp_header(streamed_conn, "content-length") == ["8"]
  end
end
