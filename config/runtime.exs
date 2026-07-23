import Config

alias Storyarn.AI.CredentialResolver.Composite
alias Storyarn.AI.CredentialResolver.Managed
alias Storyarn.AI.CredentialResolver.Personal
alias Storyarn.AI.InferenceProviders.Fireworks
alias Storyarn.AI.InferenceProviders.Personal.Anthropic, as: PersonalAnthropic
alias Storyarn.AI.InferenceProviders.Personal.DeepSeek, as: PersonalDeepSeek
alias Storyarn.AI.InferenceProviders.Personal.Google, as: PersonalGoogle
alias Storyarn.AI.InferenceProviders.Personal.Mistral, as: PersonalMistral
alias Storyarn.AI.InferenceProviders.Personal.Moonshot, as: PersonalMoonshot
alias Storyarn.AI.InferenceProviders.Personal.OpenAI, as: PersonalOpenAI
alias Storyarn.AI.InferenceProviders.Together
alias Storyarn.AI.Tasks.ManagedDiagnostic

env = fn key ->
  case System.get_env(key) do
    value when is_binary(value) ->
      value = String.trim(value)
      if value == "", do: nil, else: value

    _ ->
      nil
  end
end

required_env = fn key ->
  env.(key) ||
    raise """
    environment variable #{key} is missing.
    """
end

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

# Block search engine indexing (staging environments)
if System.get_env("NOINDEX") in ~w(true 1) do
  config :storyarn, noindex: true
end

if admin_email = System.get_env("ADMIN_EMAIL") do
  config :storyarn, :admin_email, admin_email
end

if config_env() != :test do
  config :storyarn, Storyarn.Versioning.RestorePolicy,
    sheet_version_restore: System.get_env("SHEET_VERSION_RESTORE_ENABLED") in ~w(true 1),
    flow_version_restore: System.get_env("FLOW_VERSION_RESTORE_ENABLED") in ~w(true 1),
    scene_version_restore: System.get_env("SCENE_VERSION_RESTORE_ENABLED") in ~w(true 1),
    project_snapshot_restore: System.get_env("PROJECT_SNAPSHOT_RESTORE_ENABLED") in ~w(true 1),
    deleted_project_recovery: System.get_env("DELETED_PROJECT_RECOVERY_ENABLED") in ~w(true 1)

  config :storyarn, Storyarn.Workers.DailySnapshotWorker,
    pruning_enabled: System.get_env("AUTO_SNAPSHOT_PRUNING_ENABLED") in ~w(true 1)

  config :storyarn, Storyarn.Workers.SnapshotRetentionWorker,
    enabled: System.get_env("DELETED_PROJECT_SNAPSHOT_RETENTION_ENABLED") in ~w(true 1)

  config :storyarn, Storyarn.Workers.TrashRetentionWorker,
    enabled: System.get_env("ENTITY_TRASH_RETENTION_ENABLED") in ~w(true 1)
end

managed_ai_enabled? = config_env() != :test and env.("STORYARN_AI_MANAGED_ENABLED") in ~w(true 1)
personal_ai_enabled? = config_env() != :test and env.("STORYARN_AI_PERSONAL_BYOK_ENABLED") in ~w(true 1)

inference_providers = %{}
credential_adapters = %{}
registered_tasks = []

{inference_providers, credential_adapters} =
  if personal_ai_enabled? do
    personal_provider_specs = %{
      "anthropic" => %{
        adapter: PersonalAnthropic,
        model_env: "STORYARN_AI_PERSONAL_ANTHROPIC_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_ANTHROPIC_ENDPOINT",
        endpoint: "https://api.anthropic.com/v1/messages",
        response_mode: "json_schema"
      },
      "openai" => %{
        adapter: PersonalOpenAI,
        model_env: "STORYARN_AI_PERSONAL_OPENAI_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_OPENAI_ENDPOINT",
        endpoint: "https://api.openai.com/v1/chat/completions",
        response_mode: "json_schema",
        request_overrides: %{store: false}
      },
      "google" => %{
        adapter: PersonalGoogle,
        model_env: "STORYARN_AI_PERSONAL_GOOGLE_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_GOOGLE_ENDPOINT",
        endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        response_mode: "json_schema"
      },
      "moonshot" => %{
        adapter: PersonalMoonshot,
        model_env: "STORYARN_AI_PERSONAL_MOONSHOT_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_MOONSHOT_ENDPOINT",
        endpoint: "https://api.moonshot.ai/v1/chat/completions",
        response_mode: "json_object"
      },
      "mistral" => %{
        adapter: PersonalMistral,
        model_env: "STORYARN_AI_PERSONAL_MISTRAL_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_MISTRAL_ENDPOINT",
        endpoint: "https://api.mistral.ai/v1/chat/completions",
        response_mode: "json_schema"
      },
      "deepseek" => %{
        adapter: PersonalDeepSeek,
        model_env: "STORYARN_AI_PERSONAL_DEEPSEEK_MODEL",
        endpoint_env: "STORYARN_AI_PERSONAL_DEEPSEEK_ENDPOINT",
        endpoint: "https://api.deepseek.com/chat/completions",
        response_mode: "json_object"
      }
    }

    configured_personal_providers =
      Enum.reduce(personal_provider_specs, %{}, fn {provider, spec}, acc ->
        case env.(spec.model_env) do
          nil ->
            acc

          model ->
            endpoint = env.(spec.endpoint_env) || spec.endpoint
            adapter_config = [endpoint: endpoint]

            adapter_config =
              if spec[:request_overrides],
                do: Keyword.put(adapter_config, :request_overrides, spec.request_overrides),
                else: adapter_config

            config :storyarn, spec.adapter, adapter_config

            Map.put(acc, provider, %{
              model: model,
              response_mode: spec.response_mode,
              processing_location: "provider-controlled"
            })
        end
      end)

    if map_size(configured_personal_providers) == 0 do
      raise "personal BYOK requires at least one STORYARN_AI_PERSONAL_<PROVIDER>_MODEL"
    end

    personal_inference_providers =
      Map.new(configured_personal_providers, fn {provider, _config} ->
        {provider, personal_provider_specs[provider].adapter}
      end)

    config :storyarn, Storyarn.AI.PersonalConsents,
      policy_text_version: required_env.("STORYARN_AI_PERSONAL_CONSENT_VERSION")

    config :storyarn, Storyarn.AI.PersonalProviders, providers: configured_personal_providers

    {Map.merge(inference_providers, personal_inference_providers), Map.put(credential_adapters, :personal_byok, Personal)}
  else
    {inference_providers, credential_adapters}
  end

{inference_providers, credential_adapters, registered_tasks} =
  if managed_ai_enabled? do
    if env.("STORYARN_AI_MANAGED_ZDR_VERIFIED") not in ~w(true 1) or
         env.("STORYARN_AI_MANAGED_NO_TRAINING_VERIFIED") not in ~w(true 1) do
      raise "managed AI requires explicit ZDR and no-training verification"
    end

    positive_integer = fn key ->
      case Integer.parse(required_env.(key)) do
        {value, ""} when value > 0 -> value
        _invalid -> raise "environment variable #{key} must be a positive integer"
      end
    end

    provider_configs = %{
      "fireworks" => %{
        adapter: Fireworks,
        api_key_env: "STORYARN_AI_FIREWORKS_API_KEY",
        credential_ref: "storyarn-managed-fireworks-v1",
        endpoint:
          env.("STORYARN_AI_FIREWORKS_ENDPOINT") ||
            "https://api.fireworks.ai/inference/v1/chat/completions"
      },
      "together" => %{
        adapter: Together,
        api_key_env: "STORYARN_AI_TOGETHER_API_KEY",
        credential_ref: "storyarn-managed-together-v1",
        endpoint:
          env.("STORYARN_AI_TOGETHER_ENDPOINT") ||
            "https://api.together.xyz/v1/chat/completions"
      }
    }

    provider_name = required_env.("STORYARN_AI_MANAGED_PROVIDER")

    provider_config =
      Map.get(provider_configs, provider_name) ||
        raise "STORYARN_AI_MANAGED_PROVIDER must be fireworks or together"

    credentials =
      provider_configs
      |> Enum.reduce(%{}, fn {_name, config}, acc ->
        case env.(config.api_key_env) do
          nil -> acc
          api_key -> Map.put(acc, config.credential_ref, api_key)
        end
      end)
      |> Map.put(provider_config.credential_ref, required_env.(provider_config.api_key_env))

    managed_inference_providers =
      Map.new(provider_configs, fn {name, provider} -> {name, provider.adapter} end)

    config :storyarn, Fireworks, endpoint: provider_configs["fireworks"].endpoint
    config :storyarn, Managed, credentials: credentials

    config :storyarn, ManagedDiagnostic,
      enabled: true,
      price_id: required_env.("STORYARN_AI_DIAGNOSTIC_PRICE_ID"),
      price_version: positive_integer.("STORYARN_AI_DIAGNOSTIC_PRICE_VERSION"),
      price_units: positive_integer.("STORYARN_AI_DIAGNOSTIC_PRICE_UNITS")

    config :storyarn, Storyarn.AI.RouteResolver,
      managed: [
        enabled: true,
        provider: provider_name,
        model: required_env.("STORYARN_AI_MANAGED_MODEL"),
        credential_ref: provider_config.credential_ref,
        payer: "storyarn",
        assignment_source: "operator_default",
        consent_basis: "workspace_policy",
        verified_zdr: true,
        verified_no_training: true,
        endpoint: provider_config.endpoint,
        region: required_env.("STORYARN_AI_MANAGED_REGION"),
        provider_price: [
          version: positive_integer.("STORYARN_AI_PROVIDER_PRICE_VERSION"),
          currency: required_env.("STORYARN_AI_PROVIDER_PRICE_CURRENCY"),
          input_per_million: required_env.("STORYARN_AI_PROVIDER_INPUT_PER_MILLION"),
          output_per_million: required_env.("STORYARN_AI_PROVIDER_OUTPUT_PER_MILLION"),
          max_estimated_cost: required_env.("STORYARN_AI_PROVIDER_MAX_OPERATION_COST")
        ],
        budget: [
          global_daily: required_env.("STORYARN_AI_PROVIDER_GLOBAL_DAILY_CAP"),
          global_monthly: required_env.("STORYARN_AI_PROVIDER_GLOBAL_MONTHLY_CAP"),
          workspace_daily: required_env.("STORYARN_AI_PROVIDER_WORKSPACE_DAILY_CAP")
        ]
      ]

    config :storyarn, Storyarn.AI.Settlement, Storyarn.AI.Settlement.Managed
    config :storyarn, Together, endpoint: provider_configs["together"].endpoint

    {Map.merge(inference_providers, managed_inference_providers), Map.put(credential_adapters, :managed, Managed),
     [ManagedDiagnostic | registered_tasks]}
  else
    {inference_providers, credential_adapters, registered_tasks}
  end

if map_size(credential_adapters) > 0 do
  config :storyarn, Composite, adapters: credential_adapters
  config :storyarn, Storyarn.AI.CredentialResolver, Composite
end

if map_size(inference_providers) > 0 do
  config :storyarn, Storyarn.AI.InferenceProviders, providers: inference_providers
end

if registered_tasks != [] do
  config :storyarn, Storyarn.AI.TaskRegistry, tasks: Enum.reverse(registered_tasks)
end

posthog_dotenv =
  if config_env() == :dev and File.exists?(".env") do
    ".env"
    |> File.stream!()
    |> Enum.reduce(%{}, fn line, env ->
      line = String.trim(line)

      case String.split(line, "=", parts: 2) do
        ["POSTHOG" <> _ = key, value] when key != "" ->
          Map.put(env, key, value |> String.trim() |> String.trim(~s(")) |> String.trim("'"))

        _ ->
          env
      end
    end)
  else
    %{}
  end

posthog_env = fn key, default ->
  System.get_env(key) || Map.get(posthog_dotenv, key) || default
end

config :storyarn, :contact_email, System.get_env("CONTACT_EMAIL") || "hello@storyarn.com"

if config_env() != :test do
  posthog_api_key = posthog_env.("POSTHOG_PROJECT_API_KEY", nil)
  posthog_enabled? = posthog_env.("POSTHOG_ENABLED", nil) in ~w(true 1)
  posthog_configured? = posthog_enabled? and is_binary(posthog_api_key) and posthog_api_key != ""
  posthog_frontend_enabled? = posthog_env.("POSTHOG_FRONTEND_ENABLED", "true") in ~w(true 1)
  posthog_error_tracking_enabled? = posthog_env.("POSTHOG_ERROR_TRACKING_ENABLED", "true") in ~w(true 1)

  posthog_frontend_error_tracking_enabled? =
    posthog_env.(
      "POSTHOG_FRONTEND_ERROR_TRACKING_ENABLED",
      if(posthog_error_tracking_enabled?, do: "true", else: "false")
    ) in ~w(true 1)

  posthog_host = posthog_env.("POSTHOG_HOST", "https://eu.i.posthog.com")

  config :posthog,
    enable: posthog_configured?,
    enable_error_tracking: posthog_configured? and posthog_error_tracking_enabled?,
    api_host: posthog_host,
    api_key: posthog_api_key || "",
    capture_level: :error,
    enable_source_code_context: true,
    global_properties: %{environment: to_string(config_env())},
    in_app_otp_apps: [:storyarn],
    metadata: [:request_id]

  config :storyarn, :posthog_frontend,
    frontend_enabled: posthog_configured? and posthog_frontend_enabled?,
    error_tracking_enabled: posthog_configured? and posthog_frontend_enabled? and posthog_frontend_error_tracking_enabled?
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
  if env.("REDIS_URL") do
    config :storyarn, :rate_limiter_backend, :redis
  end

  # Cloak encryption key for sensitive database fields
  # Generate with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
  cloak_key = required_env.("CLOAK_KEY")
  decoded_cloak_key = Base.decode64!(cloak_key)

  database_url = required_env.("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = required_env.("SECRET_KEY_BASE")

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

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

  # Configure Resend for production email delivery.
  # Production must not silently fall back to Swoosh.Adapters.Local.
  resend_api_key = required_env.("RESEND_API_KEY")
  mailer_from_email = required_env.("MAILER_FROM_EMAIL")
  mailer_from_name = env.("MAILER_FROM_NAME") || "Storyarn"

  # S3-compatible Storage Configuration.
  # Fly Tigris exposes AWS_* env vars. Buckets remain private: browser delivery
  # goes through authenticated Storyarn routes and short-lived signed URLs.
  # AWS_PUBLIC_URL is optional and retained only for compatible URL parsing.
  if !env.("AWS_ACCESS_KEY_ID") do
    raise """
    production object storage is missing.
    Configure Fly Tigris or another S3-compatible storage provider with
    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, BUCKET_NAME, and
    AWS_ENDPOINT_URL_S3. AWS_PUBLIC_URL is optional.
    """
  end

  s3_access_key = required_env.("AWS_ACCESS_KEY_ID")
  s3_secret_key = required_env.("AWS_SECRET_ACCESS_KEY")
  s3_bucket = required_env.("BUCKET_NAME")
  s3_endpoint = required_env.("AWS_ENDPOINT_URL_S3")
  s3_public_url = env.("AWS_PUBLIC_URL")

  %URI{host: s3_host} = URI.parse(s3_endpoint)

  config :storyarn, Storyarn.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: resend_api_key

  config :storyarn, Storyarn.Repo,
    ssl: if(System.get_env("DATABASE_SSL") == "false", do: false, else: true),
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  config :storyarn, Storyarn.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: decoded_cloak_key, iv_length: 12
      }
    ]

  config :storyarn, StoryarnWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind on all IPv4 and IPv6 interfaces.
      # Fly.io health checks connect via IPv4 (0.0.0.0), so we must listen on IPv4.
      ip: {0, 0, 0, 0},
      # Session and LiveView salts are compile-time values (used in endpoint.ex
      # with compile_env!). They are set in config.exs and cannot be overridden
      # at runtime. Security comes from SECRET_KEY_BASE, not these salts.
      port: port
    ],
    secret_key_base: secret_key_base

  config :storyarn, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :storyarn,
         :import_idempotency_secret,
         :crypto.mac(:hmac, :sha256, decoded_cloak_key, "storyarn/import-idempotency/v1")

  # Default "from" email address (tuple format matching notifier expectations)
  config :storyarn, :mailer_sender, {mailer_from_name, mailer_from_email}

  if is_nil(s3_host) do
    raise "object storage endpoint URL must include a host"
  end

  config :ex_aws, :s3,
    host: s3_host,
    scheme: "https://"

  config :ex_aws,
    access_key_id: s3_access_key,
    secret_access_key: s3_secret_key

  config :storyarn, :r2,
    bucket: s3_bucket,
    public_url: s3_public_url,
    endpoint_url: s3_endpoint

  config :storyarn, :storage, adapter: :r2
end
