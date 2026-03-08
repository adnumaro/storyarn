import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/storyarn start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :storyarn, StoryarnWeb.Endpoint, server: true
end

# Sentry error tracking
if sentry_dsn = System.get_env("SENTRY_DSN") do
  config :sentry, dsn: sentry_dsn

  config :logger, :sentry,
    level: :error,
    metadata: [:request_id, :user_id]
end

# Trust X-Forwarded-For header when behind a reverse proxy (CloudFlare, AWS ELB, etc.)
# Only enable this in production when you're certain you're behind a trusted proxy
# Without this, rate limiting uses the direct connection IP (more secure default)
if System.get_env("TRUST_PROXY") in ~w(true 1) do
  config :storyarn, trust_proxy: true
end

# Rate limiting with Redis for production (multi-node support)
# Development and test use ETS backend (started in application.ex)
if config_env() == :prod do
  if System.get_env("REDIS_URL") do
    config :storyarn, :rate_limiter_backend, :redis
  end

  # Cloak encryption key for OAuth tokens
  # Generate with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
      """

  config :storyarn, Storyarn.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12
      }
    ]

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :storyarn, Storyarn.Repo,
    ssl: if(System.get_env("DATABASE_SSL") != "false", do: true, else: false),
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :storyarn, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Session and LiveView salts are compile-time values (used in endpoint.ex
  # with compile_env!). They are set in config.exs and cannot be overridden
  # at runtime. Security comes from SECRET_KEY_BASE, not these salts.

  config :storyarn, StoryarnWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :storyarn, StoryarnWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :storyarn, StoryarnWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Configure Resend for production email delivery
  # Get your API key at https://resend.com
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :storyarn, Storyarn.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key
  end

  # Default "from" email address
  config :storyarn, :mailer_from,
    email: System.get_env("MAILER_FROM_EMAIL", "noreply@storyarn.com"),
    name: System.get_env("MAILER_FROM_NAME", "Storyarn")

  # S3-compatible Storage Configuration
  # Supports Cloudflare R2 (R2_* vars) and Fly Tigris (AWS_* vars)
  {s3_access_key, s3_secret_key, s3_bucket, s3_endpoint, s3_public_url} =
    cond do
      System.get_env("R2_ACCESS_KEY_ID") ->
        {
          System.get_env("R2_ACCESS_KEY_ID"),
          System.get_env("R2_SECRET_ACCESS_KEY") ||
            raise("R2_SECRET_ACCESS_KEY is required when R2_ACCESS_KEY_ID is set"),
          System.get_env("R2_BUCKET") ||
            raise("R2_BUCKET is required when R2_ACCESS_KEY_ID is set"),
          System.get_env("R2_ENDPOINT_URL") ||
            raise("R2_ENDPOINT_URL is required when R2_ACCESS_KEY_ID is set"),
          System.get_env("R2_PUBLIC_URL")
        }

      System.get_env("AWS_ACCESS_KEY_ID") ->
        {
          System.get_env("AWS_ACCESS_KEY_ID"),
          System.get_env("AWS_SECRET_ACCESS_KEY") ||
            raise("AWS_SECRET_ACCESS_KEY is required when AWS_ACCESS_KEY_ID is set"),
          System.get_env("BUCKET_NAME") ||
            raise("BUCKET_NAME is required when AWS_ACCESS_KEY_ID is set"),
          System.get_env("AWS_ENDPOINT_URL_S3") ||
            raise("AWS_ENDPOINT_URL_S3 is required when AWS_ACCESS_KEY_ID is set"),
          System.get_env("AWS_PUBLIC_URL")
        }

      true ->
        {nil, nil, nil, nil, nil}
    end

  if s3_access_key do
    %URI{host: s3_host} = URI.parse(s3_endpoint)

    config :ex_aws,
      access_key_id: s3_access_key,
      secret_access_key: s3_secret_key

    config :ex_aws, :s3,
      host: s3_host,
      scheme: "https://"

    config :storyarn, :r2,
      bucket: s3_bucket,
      public_url: s3_public_url,
      endpoint_url: s3_endpoint

    config :storyarn, :storage, adapter: :r2
  end
end
