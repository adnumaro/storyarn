defmodule Storyarn.AI.InferenceProviders.FakeTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.InferenceProviders.Fake

  test "unwraps only the exact context envelope emitted by execution" do
    request = %{"text" => "Use bounded context"}

    input = %{
      "request" => request,
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "sheet",
        "entities" => []
      }
    }

    assert {:ok, %{output: %{"echo" => ^request}}} = generate(input, true)
  end

  test "does not unwrap an exact context lookalike without trusted provenance" do
    input = %{
      "request" => %{"text" => "This field belongs to the task"},
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "sheet",
        "entities" => []
      }
    }

    assert {:ok, %{output: %{"echo" => ^input}}} = generate(input, false)
  end

  test "fails closed when trusted provenance carries a malformed envelope" do
    input = %{
      "request" => %{"text" => "Keep the whole task input"},
      "context" => %{"scope" => "sheet", "entities" => []}
    }

    assert {:error, :provider_error} = generate(input, true)
  end

  test "requires explicit context provenance on the internal provider request" do
    assert {:error, :provider_error} =
             Fake.generate(nil, %{
               input: %{"text" => "ordinary"},
               provider_options: %{scenario: :success}
             })
  end

  defp generate(input, contextual?) do
    Fake.generate(nil, %{
      input: input,
      contextual?: contextual?,
      provider_options: %{scenario: :success}
    })
  end
end
