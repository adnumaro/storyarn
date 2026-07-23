defmodule StoryarnTest.AI.ContractTask do
  @moduledoc false
  @behaviour Storyarn.AI.TaskDefinition

  @impl true
  def definition do
    config = Application.get_env(:storyarn, __MODULE__, [])

    %{
      id: "contract.echo",
      capability: :suggestions,
      data_scope: :project,
      required_domain_permissions: %{execute: :view, apply: :edit_content},
      allowed_lanes: Keyword.get(config, :allowed_lanes, [:managed]),
      input_schema_version: "contract-input-v1",
      output_schema_version: "contract-output-v1",
      prompt_version: "contract-prompt-v1",
      context_version: "none-v1",
      max_input_bytes: 4_096,
      max_output_bytes: 8_192,
      execution_mode: Keyword.get(config, :execution_mode, :inline),
      timeout_ms: 1_000,
      result_type: "contract_echo",
      result_destination: %{type: :panel, id: "contract-result"},
      result_ttl_seconds: Keyword.get(config, :result_ttl_seconds, 86_400),
      personal_byok_allowed?: Keyword.get(config, :personal_byok_allowed?, false),
      personal_cost_class: Keyword.get(config, :personal_cost_class),
      bulk_allowed?: false,
      scheduled_allowed?: Keyword.get(config, :scheduled_allowed?, false),
      result_visibility: :actor_private,
      managed_price: Keyword.get(config, :managed_price, %{id: "contract-free", version: 1, units: 1}),
      enabled?: Keyword.get(config, :enabled, true),
      command_ids: ["ai.contract.echo"],
      provider_options: %{
        scenario: Keyword.get(config, :scenario, :success),
        system_prompt: "Return only JSON matching the requested schema.",
        schema_name: "contract_echo",
        response_schema: %{
          "type" => "object",
          "properties" => %{
            "echo" => %{
              "type" => "object",
              "properties" => %{"text" => %{"type" => "string"}},
              "required" => ["text"],
              "additionalProperties" => false
            }
          },
          "required" => ["echo"],
          "additionalProperties" => false
        },
        max_output_tokens: 512,
        temperature: 0
      }
    }
  end

  @impl true
  def validate_input(%{"text" => text}) when is_binary(text), do: :ok
  def validate_input(_input), do: {:error, :invalid_contract_input}

  @impl true
  def validate_output(%{"echo" => %{"text" => text}}) when is_binary(text), do: :ok
  def validate_output(_output), do: {:error, :invalid_contract_output}
end
