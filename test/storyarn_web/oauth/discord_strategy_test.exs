defmodule StoryarnWeb.OAuth.DiscordStrategyTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.OAuth.DiscordStrategy
  alias Ueberauth.Auth.{Credentials, Extra, Info}

  # =============================================================================
  # uid/1
  # =============================================================================

  describe "uid/1" do
    test "extracts user ID from conn private" do
      conn = conn_with_user(%{"id" => "123456789"})
      assert DiscordStrategy.uid(conn) == "123456789"
    end
  end

  # =============================================================================
  # info/1
  # =============================================================================

  describe "info/1" do
    test "builds Info struct with email, image, and nickname" do
      user = %{
        "id" => "123",
        "email" => "user@example.com",
        "username" => "testuser",
        "avatar" => "abc123def"
      }

      conn = conn_with_user(user)
      info = DiscordStrategy.info(conn)

      assert %Info{} = info
      assert info.email == "user@example.com"
      assert info.nickname == "testuser"
      assert info.image == "https://cdn.discordapp.com/avatars/123/abc123def.jpg"
    end

    test "uses default avatar when user has no custom avatar" do
      user = %{
        "id" => "123",
        "email" => "user@example.com",
        "username" => "testuser",
        "avatar" => nil,
        "discriminator" => "1234"
      }

      conn = conn_with_user(user)
      info = DiscordStrategy.info(conn)

      # discriminator 1234 mod 5 = 4
      assert info.image == "https://cdn.discordapp.com/embed/avatars/4.png"
    end

    test "handles nil discriminator for default avatar" do
      user = %{
        "id" => "123",
        "email" => nil,
        "username" => "nodisc",
        "avatar" => nil,
        "discriminator" => nil
      }

      conn = conn_with_user(user)
      info = DiscordStrategy.info(conn)

      # nil discriminator falls back to "0", 0 mod 5 = 0
      assert info.image == "https://cdn.discordapp.com/embed/avatars/0.png"
    end
  end

  # =============================================================================
  # credentials/1
  # =============================================================================

  describe "credentials/1" do
    test "builds Credentials struct from token" do
      token = %OAuth2.AccessToken{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: 1_700_000_000,
        other_params: %{"scope" => "identify email"}
      }

      conn = conn_with_token(token)
      creds = DiscordStrategy.credentials(conn)

      assert %Credentials{} = creds
      assert creds.token == "test_access_token"
      assert creds.refresh_token == "test_refresh_token"
      assert creds.expires == true
      assert creds.expires_at == 1_700_000_000
      assert creds.scopes == ["identify", "email"]
    end

    test "handles missing scope in token" do
      token = %OAuth2.AccessToken{
        access_token: "token",
        refresh_token: nil,
        expires_at: nil,
        other_params: %{}
      }

      conn = conn_with_token(token)
      creds = DiscordStrategy.credentials(conn)

      assert creds.expires == false
      assert creds.scopes == [""]
    end
  end

  # =============================================================================
  # extra/1
  # =============================================================================

  describe "extra/1" do
    test "includes token and user in raw_info" do
      token = %OAuth2.AccessToken{access_token: "tok", other_params: %{}}
      user = %{"id" => "123", "username" => "test"}

      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:discord_token, token)
        |> Plug.Conn.put_private(:discord_user, user)
        |> put_ueberauth_options()

      extra = DiscordStrategy.extra(conn)

      assert %Extra{} = extra
      assert extra.raw_info[:token] == token
      assert extra.raw_info[:user] == user
    end

    test "includes keys present in private even if nil, excludes absent keys" do
      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:discord_token, nil)
        |> put_ueberauth_options()

      extra = DiscordStrategy.extra(conn)

      # discord_token exists in private (even if nil) → included as :token
      assert Map.has_key?(extra.raw_info, :token)
      assert extra.raw_info[:token] == nil
      # discord_user was never put_private'd → excluded
      refute Map.has_key?(extra.raw_info, :user)
    end
  end

  # =============================================================================
  # handle_cleanup!/1
  # =============================================================================

  describe "handle_cleanup!/1" do
    test "clears discord_token and discord_user from conn private" do
      token = %OAuth2.AccessToken{access_token: "tok", other_params: %{}}

      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:discord_token, token)
        |> Plug.Conn.put_private(:discord_user, %{"id" => "123"})
        |> put_ueberauth_options()

      cleaned = DiscordStrategy.handle_cleanup!(conn)

      assert cleaned.private.discord_token == nil
      assert cleaned.private.discord_user == nil
    end
  end

  # =============================================================================
  # handle_callback!/1 — missing code path
  # =============================================================================

  describe "handle_callback!/1 without code" do
    test "sets missing_code error" do
      conn =
        %Plug.Conn{params: %{}}
        |> put_ueberauth_options()

      result = DiscordStrategy.handle_callback!(conn)

      assert result.assigns.ueberauth_failure
      errors = result.assigns.ueberauth_failure.errors
      assert length(errors) == 1
      assert hd(errors).message_key == "missing_code"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp conn_with_user(user) do
    %Plug.Conn{}
    |> Plug.Conn.put_private(:discord_user, user)
    |> put_ueberauth_options()
  end

  defp conn_with_token(token) do
    %Plug.Conn{}
    |> Plug.Conn.put_private(:discord_token, token)
    |> put_ueberauth_options()
  end

  defp put_ueberauth_options(conn) do
    Plug.Conn.put_private(conn, :ueberauth_request_options, %{
      options: [uid_field: :id, default_scope: "identify"],
      callback_methods: ["GET"],
      callback_params: []
    })
  end
end
