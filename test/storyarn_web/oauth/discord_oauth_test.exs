defmodule StoryarnWeb.OAuth.DiscordOAuthTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.OAuth.DiscordOAuth

  describe "client/1" do
    test "builds client with correct Discord API defaults" do
      client = DiscordOAuth.client()

      assert client.site == "https://discord.com/api"
      assert client.authorize_url == "https://discord.com/api/oauth2/authorize"
      assert client.token_url == "https://discord.com/api/oauth2/token"
    end

    test "merges custom opts over defaults" do
      client = DiscordOAuth.client(site: "https://custom.example.com")

      assert client.site == "https://custom.example.com"
      # Other defaults remain
      assert client.authorize_url == "https://discord.com/api/oauth2/authorize"
    end

    test "configures JSON serializer" do
      client = DiscordOAuth.client()

      assert Map.has_key?(client.serializers, "application/json")
    end
  end

  describe "authorize_url!/2" do
    test "generates Discord authorization URL" do
      url = DiscordOAuth.authorize_url!(scope: "identify email")

      assert url =~ "https://discord.com/api/oauth2/authorize"
      assert url =~ "scope=identify+email"
      assert url =~ "response_type=code"
    end
  end
end
