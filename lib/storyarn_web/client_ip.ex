defmodule StoryarnWeb.ClientIp do
  @moduledoc """
  Normalizes client IP values for rate-limit keys and audit metadata.
  """

  @missing_peer_data "missing_peer_data"
  @trusted_proxy_headers ~w[fly-client-ip x-forwarded-for]

  def missing_peer_data, do: @missing_peer_data
  def trusted_proxy_headers, do: @trusted_proxy_headers

  def from_socket(socket) do
    if trust_proxy?() do
      socket
      |> trusted_proxy_ip()
      |> case do
        address when is_tuple(address) -> format_address(address)
        _ -> peer_data_ip(socket)
      end
    else
      peer_data_ip(socket)
    end
  end

  def from_conn(%Plug.Conn{remote_ip: address}), do: format_address(address)
  def from_conn(_conn), do: @missing_peer_data

  defp trust_proxy? do
    Application.get_env(:storyarn, :trust_proxy, false)
  end

  defp trusted_proxy_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
      headers when is_list(headers) -> RemoteIp.from(headers, headers: @trusted_proxy_headers)
      _ -> nil
    end
  end

  defp peer_data_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> format_address(address)
      _ -> @missing_peer_data
    end
  end

  defp format_address(address) when is_tuple(address) do
    address
    |> :inet.ntoa()
    |> to_string()
  end

  defp format_address(_address), do: @missing_peer_data
end
