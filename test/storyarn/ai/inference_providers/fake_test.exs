defmodule Storyarn.AI.InferenceProviders.FakeTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.InferenceProviders.Fake
  alias Storyarn.AI.Tasks.FlowFindingExplanation

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

  describe "schema-derived output" do
    test "answers a registered task with a minimal instance of its own contract" do
      %{provider_options: options} = FlowFindingExplanation.definition()

      assert {:ok, %{output: output}} =
               Fake.generate(nil, %{
                 input: contextual_input(),
                 contextual?: true,
                 provider_options: options
               })

      # The point of the schema scenario: the task's OWN validator accepts it.
      assert :ok = FlowFindingExplanation.validate_output(output)
      assert Enum.sort(Map.keys(output)) == ~w(implications suggested_checks summary why_it_triggers)
      refute Map.has_key?(output, "finding_id")
    end

    test "respects the declared bounds" do
      options = %{
        response_schema: %{
          "type" => "object",
          "properties" => %{
            "tight" => %{"type" => "string", "maxLength" => 4},
            "items" => %{"type" => "array", "items" => %{"type" => "string", "maxLength" => 3}}
          },
          "required" => ["tight", "items"]
        }
      }

      assert {:ok, %{output: %{"tight" => tight, "items" => [item]}}} =
               Fake.generate(nil, %{input: %{}, contextual?: false, provider_options: options})

      assert String.length(tight) <= 4
      assert String.length(item) <= 3
    end

    test "fails closed on a shape no registered task may declare" do
      for schema <- [
            %{"type" => "object", "properties" => %{"n" => %{"type" => "number"}}, "required" => ["n"]},
            %{"type" => "array"},
            %{},
            nil
          ] do
        assert {:error, :provider_error} =
                 Fake.generate(nil, %{
                   input: %{},
                   contextual?: false,
                   provider_options: %{response_schema: schema}
                 })
      end
    end
  end

  defp contextual_input do
    %{
      "request" => %{"locale" => "en"},
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "structural_finding",
        "entities" => []
      }
    }
  end

  defp generate(input, contextual?) do
    Fake.generate(nil, %{
      input: input,
      contextual?: contextual?,
      provider_options: %{scenario: :success}
    })
  end
end
