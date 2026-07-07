defmodule StoryarnWeb.ClientIpTest do
  use StoryarnWeb.ConnCase, async: false

  alias StoryarnWeb.ClientIp

  setup do
    original_trust_proxy = Application.get_env(:storyarn, :trust_proxy, false)

    on_exit(fn ->
      Application.put_env(:storyarn, :trust_proxy, original_trust_proxy)
    end)
  end

  test "formats IPv4 conn remote_ip", %{conn: conn} do
    conn = %{conn | remote_ip: {127, 0, 0, 1}}

    assert ClientIp.from_conn(conn) == "127.0.0.1"
  end

  test "formats IPv6 conn remote_ip", %{conn: conn} do
    conn = %{conn | remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}

    assert ClientIp.from_conn(conn) == "::1"
  end

  test "uses an explicit operational key when peer data is unavailable" do
    assert ClientIp.from_conn(%{}) == "missing_peer_data"
    assert ClientIp.missing_peer_data() == "missing_peer_data"
  end

  test "uses trusted proxy headers from LiveView sockets when trust_proxy is enabled" do
    Application.put_env(:storyarn, :trust_proxy, true)

    socket =
      socket_with_connect_info(%{
        peer_data: %{address: {10, 0, 0, 1}},
        x_headers: [{"fly-client-ip", "203.0.113.10"}]
      })

    assert ClientIp.from_socket(socket) == "203.0.113.10"
  end

  test "ignores LiveView proxy headers when trust_proxy is disabled" do
    Application.put_env(:storyarn, :trust_proxy, false)

    socket =
      socket_with_connect_info(%{
        peer_data: %{address: {10, 0, 0, 1}},
        x_headers: [{"fly-client-ip", "203.0.113.10"}]
      })

    assert ClientIp.from_socket(socket) == "10.0.0.1"
  end

  test "falls back to LiveView peer_data when trusted proxy headers are unavailable" do
    Application.put_env(:storyarn, :trust_proxy, true)

    socket =
      socket_with_connect_info(%{
        peer_data: %{address: {10, 0, 0, 1}},
        x_headers: []
      })

    assert ClientIp.from_socket(socket) == "10.0.0.1"
  end

  defp socket_with_connect_info(connect_info) do
    %Phoenix.LiveView.Socket{private: %{connect_info: connect_info}}
  end
end
