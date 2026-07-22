defmodule Storyarn.AI.Tasks.ManagedDiagnostic do
  @moduledoc "Operator-only, content-free production diagnostic for the managed provider path."
  @behaviour Storyarn.AI.TaskDefinition

  @probe "storyarn-managed-ai-diagnostic-v1"

  @impl true
  def definition do
    config = Application.get_env(:storyarn, __MODULE__, [])

    %{
      id: "operator.managed_diagnostic",
      capability: :tasks,
      data_scope: :workspace,
      required_domain_permissions: %{execute: :manage_workspace},
      allowed_lanes: [:managed],
      input_schema_version: "managed-diagnostic-input-v1",
      output_schema_version: "managed-diagnostic-output-v1",
      prompt_version: "managed-diagnostic-prompt-v1",
      context_version: "none-v1",
      max_input_bytes: 256,
      max_output_bytes: 256,
      execution_mode: :inline,
      timeout_ms: 30_000,
      result_type: "managed_diagnostic_v1",
      result_destination: %{type: :none},
      result_ttl_seconds: 300,
      personal_byok_allowed?: false,
      bulk_allowed?: false,
      scheduled_allowed?: false,
      result_visibility: :actor_private,
      managed_price: %{
        id: Keyword.get(config, :price_id, "managed-diagnostic-beta"),
        version: Keyword.get(config, :price_version, 1),
        units: Keyword.get(config, :price_units, 1)
      },
      enabled?: Keyword.get(config, :enabled, false),
      command_ids: [],
      provider_options: %{
        system_prompt:
          "This is a health check. Return only a JSON object with status set to ok. Do not add other fields.",
        schema_name: "storyarn_managed_diagnostic",
        response_schema: %{
          "type" => "object",
          "properties" => %{"status" => %{"type" => "string", "enum" => ["ok"]}},
          "required" => ["status"],
          "additionalProperties" => false
        },
        max_output_tokens: 32,
        temperature: 0
      }
    }
  end

  @impl true
  def validate_input(%{"probe" => @probe}), do: :ok
  def validate_input(_input), do: {:error, :invalid_diagnostic_input}

  @impl true
  def validate_output(%{"status" => "ok"}), do: :ok
  def validate_output(_output), do: {:error, :invalid_diagnostic_output}

  def probe, do: @probe
end
