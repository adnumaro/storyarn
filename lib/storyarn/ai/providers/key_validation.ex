defmodule Storyarn.AI.Providers.KeyValidation do
  @moduledoc """
  Shared HTTP plumbing for BYOK key-validation calls.

  Every provider adapter validates keys the same way: a cheap GET against the
  provider's models endpoint, classified into `Storyarn.AI.Provider` result
  tuples. Adapters supply their base URL, path, and auth headers; this module
  resolves the per-adapter app-env overrides (`:base_url` for pointing at a
  different host, `:req_options` for injecting `Req.Test` plugs in tests).

  Adapters with non-standard status semantics (e.g. Google returns 400 for a
  bad key) pattern-match those statuses before delegating to `classify/1`.
  """

  alias Storyarn.AI.Provider

  @receive_timeout_ms 10_000

  @doc """
  Perform the validation GET request for `config_mod`.

  Options:

    * `:default_base_url` (required) — used unless the adapter's app env sets `:base_url`.
    * `:url` (required) — request path, e.g. `"/v1/models"`.
    * `:headers` — auth headers for the provider.
  """
  @spec get(module(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def get(config_mod, opts) do
    {default_base_url, opts} = Keyword.pop!(opts, :default_base_url)
    {url, opts} = Keyword.pop!(opts, :url)

    config = Application.get_env(:storyarn, config_mod, [])

    base_opts = [
      base_url: Keyword.get(config, :base_url, default_base_url),
      receive_timeout: @receive_timeout_ms,
      retry: false
    ]

    Req.get(base_opts ++ opts ++ Keyword.get(config, :req_options, []), url: url)
  end

  @doc """
  Map a `Req` result to the `Storyarn.AI.Provider.validate_key/1` contract.

  200 carries no account info by default — providers that expose account
  details parse the body themselves before falling back to this.
  """
  @spec classify({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, Provider.account_info()} | {:error, Provider.validation_error()}
  def classify({:ok, %Req.Response{status: 200}}), do: {:ok, %{account_email: nil, account_display_name: nil}}

  def classify({:ok, %Req.Response{status: status}}) when status in [401, 403], do: {:error, :invalid_key}

  def classify({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}

  def classify({:ok, %Req.Response{status: status}}) when status >= 500, do: {:error, :provider_error}

  def classify({:ok, %Req.Response{status: status}}), do: {:error, {:unexpected_status, status}}

  def classify({:error, _reason}), do: {:error, :network_error}
end
