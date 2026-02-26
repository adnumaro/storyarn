defmodule StoryarnWeb.OAuth.DiscordOAuth do
  @moduledoc """
  OAuth2 client for Discord.

  Vendored from `ueberauth_discord` (dormant since 2022) to own the code.

  Configure credentials in config:

      config :ueberauth, StoryarnWeb.OAuth.DiscordOAuth,
        client_id: System.get_env("DISCORD_CLIENT_ID"),
        client_secret: System.get_env("DISCORD_CLIENT_SECRET")
  """

  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://discord.com/api",
    authorize_url: "https://discord.com/api/oauth2/authorize",
    token_url: "https://discord.com/api/oauth2/token"
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    json_library = Ueberauth.json_library()

    OAuth2.Client.new(opts)
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  def get(token, url, headers \\ [], opts \\ []) do
    client(token: token)
    |> put_param("client_secret", client().client_secret)
    |> OAuth2.Client.get(url, headers, opts)
  end

  def get_token!(params \\ [], opts \\ []) do
    client =
      opts
      |> client()
      |> OAuth2.Client.get_token!(params)

    client.token
  end

  # Strategy Callbacks

  @impl true
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl true
  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
