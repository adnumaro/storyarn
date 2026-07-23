defmodule Storyarn.AI.Context.ModelLimitsTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.Context.ModelLimits
  alias Storyarn.AI.ModelCatalog

  setup do
    original = Application.fetch_env(:storyarn, ModelCatalog)
    Application.delete_env(:storyarn, ModelCatalog)

    on_exit(fn ->
      case original do
        {:ok, config} -> Application.put_env(:storyarn, ModelCatalog, config)
        :error -> Application.delete_env(:storyarn, ModelCatalog)
      end
    end)
  end

  test "accepts contextual input within the curated provider contract" do
    request = request("accounts/fireworks/models/qwen3p7-plus", contextual_input("bounded"), 1_024)

    assert :ok =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("bounded", 1_024)
             )
  end

  test "fails closed when a contextual model has no curated limits" do
    request = request("provider/unknown", contextual_input("bounded"), 1_024)

    assert {:error, :model_context_limits_unavailable} =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("bounded", 1_024)
             )
  end

  test "rejects output and combined context above the curated limits" do
    excessive_output = request("accounts/fireworks/models/qwen3p7-plus", contextual_input("bounded"), 65_537)

    assert {:error, :model_output_limit_exceeded} =
             ModelLimits.validate_provider_request(
               "fireworks",
               excessive_output,
               request_body("bounded", 65_537)
             )

    oversized = String.duplicate("x", 262_144)
    excessive_context = request("accounts/fireworks/models/qwen3p7-plus", contextual_input(oversized), 1_024)

    assert {:error, :model_context_window_exceeded} =
             ModelLimits.validate_provider_request(
               "fireworks",
               excessive_context,
               request_body(oversized, 1_024)
             )
  end

  test "does not apply contextual limits to ordinary task input" do
    request = request("provider/unknown", %{"request" => %{"text" => "ordinary"}}, 1_024, false)

    assert :ok =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("ordinary", 1_024)
             )
  end

  test "does not trust an exact context lookalike without the executor marker" do
    request = request("provider/unknown", contextual_input("caller controlled"), 1_024, false)

    assert :ok =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("caller controlled", 1_024)
             )
  end

  test "fails closed when the executor marks malformed contextual input" do
    request =
      request(
        "accounts/fireworks/models/qwen3p7-plus",
        %{"request" => %{"text" => "missing context"}},
        1_024
      )

    assert {:error, :model_context_limits_unavailable} =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("missing context", 1_024)
             )
  end

  test "fails closed when the internal request omits context provenance" do
    request =
      "accounts/fireworks/models/qwen3p7-plus"
      |> request(contextual_input("bounded"), 1_024)
      |> Map.delete(:contextual?)

    assert {:error, :model_context_limits_unavailable} =
             ModelLimits.validate_provider_request(
               "fireworks",
               request,
               request_body("bounded", 1_024)
             )
  end

  test "public route statuses expose only the bounded error classification" do
    for reason <- [
          :model_context_limits_unavailable,
          :model_context_window_exceeded,
          :model_output_limit_exceeded
        ] do
      assert ModelLimits.context_limit_error?(reason)
      assert ModelLimits.public_status(reason) == reason
    end

    refute ModelLimits.context_limit_error?(%{input_bytes: 42, content: "private"})
  end

  defp request(model, input, max_output_tokens, contextual? \\ true) do
    %{
      model: model,
      input: input,
      contextual?: contextual?,
      provider_options: %{max_output_tokens: max_output_tokens}
    }
  end

  defp contextual_input(text) do
    %{
      "request" => %{"text" => text},
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "sheet",
        "entities" => []
      }
    }
  end

  defp request_body(text, max_output_tokens) do
    %{
      model: "accounts/fireworks/models/qwen3p7-plus",
      messages: [
        %{role: "system", content: "Return JSON."},
        %{role: "user", content: text}
      ],
      max_tokens: max_output_tokens
    }
  end
end
