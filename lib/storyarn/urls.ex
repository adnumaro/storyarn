defmodule Storyarn.Urls do
  @moduledoc """
  Domain-layer URL helpers.

  Provides base URL resolution without depending on `StoryarnWeb.Endpoint`,
  breaking the domain→web compile cycle.
  """

  @doc """
  Returns the application's base URL (e.g. "https://storyarn.com").

  Reads from the endpoint configuration at runtime, same value as
  `StoryarnWeb.Endpoint.url/0` but without the compile-time dependency.
  """
  def base_url do
    endpoint_config = Application.get_env(:storyarn, StoryarnWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])

    scheme = Keyword.get(url_config, :scheme, "http")
    host = Keyword.get(url_config, :host, "localhost")
    port = Keyword.get(url_config, :port, 4000)

    case {scheme, port} do
      {"https", 443} -> "#{scheme}://#{host}"
      {"http", 80} -> "#{scheme}://#{host}"
      _ -> "#{scheme}://#{host}:#{port}"
    end
  end
end
