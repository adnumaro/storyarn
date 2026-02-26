defmodule StoryarnWeb.OAuth.DiscordStrategy do
  @moduledoc """
  Ueberauth Strategy for Discord OAuth2.

  Vendored from `ueberauth_discord` (dormant since 2022) to own the code.
  Discord's OAuth2 API is stable and unlikely to change.

  ## Configuration

      config :ueberauth, Ueberauth,
        providers: [
          discord: {StoryarnWeb.OAuth.DiscordStrategy, [default_scope: "identify email"]}
        ]

      config :ueberauth, StoryarnWeb.OAuth.DiscordOAuth,
        client_id: System.get_env("DISCORD_CLIENT_ID"),
        client_secret: System.get_env("DISCORD_CLIENT_SECRET")
  """

  use Ueberauth.Strategy, uid_field: :id, default_scope: "identify"

  alias Ueberauth.Auth.{Credentials, Extra, Info}

  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts =
      [scope: scopes]
      |> with_optional_param(:prompt, conn)
      |> with_optional_param(:permissions, conn)
      |> with_optional_param(:guild_id, conn)
      |> with_optional_param(:disable_guild_select, conn)
      |> with_state_param(conn)
      |> Keyword.put(:redirect_uri, callback_url(conn))

    redirect!(conn, StoryarnWeb.OAuth.DiscordOAuth.authorize_url!(opts))
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]
    token = StoryarnWeb.OAuth.DiscordOAuth.get_token!([code: code], opts)

    if token.access_token == nil do
      err = token.other_params["error"]
      desc = token.other_params["error_description"]
      set_errors!(conn, [error(err, desc)])
    else
      conn
      |> put_private(:discord_token, token)
      |> fetch_user(token)
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:discord_token, nil)
    |> put_private(:discord_user, nil)
  end

  def credentials(conn) do
    token = conn.private.discord_token
    scopes = split_scopes(token)

    %Credentials{
      expires: !!token.expires_at,
      expires_at: token.expires_at,
      scopes: scopes,
      refresh_token: token.refresh_token,
      token: token.access_token
    }
  end

  def info(conn) do
    user = conn.private.discord_user

    %Info{
      email: user["email"],
      image: fetch_image(user),
      nickname: user["username"]
    }
  end

  def extra(conn) do
    raw =
      %{discord_token: :token, discord_user: :user}
      |> Enum.filter(fn {key, _} -> Map.has_key?(conn.private, key) end)
      |> Enum.map(fn {key, mapped} -> {mapped, Map.fetch!(conn.private, key)} end)
      |> Map.new()

    %Extra{raw_info: raw}
  end

  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string()

    conn.private.discord_user[uid_field]
  end

  # Private

  defp fetch_user(conn, token) do
    path = "https://discord.com/api/users/@me"

    case StoryarnWeb.OAuth.DiscordOAuth.get(token, path) do
      {:ok, %OAuth2.Response{status_code: 401}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: status_code, body: user}}
      when status_code in 200..399 ->
        put_private(conn, :discord_user, user)

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  defp fetch_image(user) do
    if user["avatar"] do
      "https://cdn.discordapp.com/avatars/#{user["id"]}/#{user["avatar"]}.jpg"
    else
      discriminator = user["discriminator"] || "0"
      index = Integer.mod(String.to_integer(discriminator), 5)
      "https://cdn.discordapp.com/embed/avatars/#{index}.png"
    end
  end

  defp split_scopes(token) do
    (token.other_params["scope"] || "")
    |> String.split(" ")
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp with_optional_param(opts, key, conn) do
    case conn.params[to_string(key)] || option(conn, key) do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end
end
