defmodule Storyarn.AI.InferenceProviders.FakeTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.InferenceProviders.Fake
  alias Storyarn.AI.Tasks.ManagedDiagnostic
  alias Storyarn.Sheets.AI.ContextContract
  alias StoryarnTest.AI.ContractTask

  test "unwraps only the exact context envelope emitted by execution" do
    request = %{"text" => "Use bounded context"}

    assert {:ok, %{output: %{"echo" => ^request}}} = generate(contextual_input(request), true)
  end

  test "does not unwrap an exact context lookalike without trusted provenance" do
    input = contextual_input(%{"text" => "This field belongs to the task"})

    assert {:ok, %{output: %{"echo" => ^input}}} = generate(input, false)
  end

  test "fails closed when trusted provenance carries a malformed envelope" do
    input = contextual_input(%{"text" => "Keep the whole task input"}, omit: ["version"])

    assert {:error, :provider_error} = generate(input, true)
  end

  test "requires explicit context provenance on the internal provider request" do
    assert {:error, :provider_error} =
             Fake.generate(nil, %{
               input: %{"text" => "ordinary"},
               context_policy: nil,
               provider_options: %{scenario: :success}
             })
  end

  describe "schema-derived output" do
    test "answers a registered task with a minimal instance of its own contract" do
      # Exercised through a fixture task since Slice 7.1a.0 removed the production
      # one this used to use. What matters is unchanged: the schema scenario must
      # produce something the task's OWN validator accepts.
      %{provider_options: options} = ContractTask.definition()

      assert {:ok, %{output: output}} =
               Fake.generate(nil, %{
                 input: contextual_input(%{"text" => "hello"}),
                 contextual?: true,
                 context_policy: context_policy(),
                 provider_options: options
               })

      assert :ok = ContractTask.validate_output(output)
      assert Map.keys(output) == ["echo"]
    end

    # The operator diagnostic is the health check for the managed path: a
    # generic string here reports the path broken when it is not.
    test "answers an enum-constrained contract with a value its validator accepts" do
      %{provider_options: options} = ManagedDiagnostic.definition()

      assert {:ok, %{output: output}} =
               Fake.generate(nil, %{
                 input: %{"probe" => ManagedDiagnostic.probe()},
                 contextual?: false,
                 context_policy: nil,
                 provider_options: options
               })

      assert :ok = ManagedDiagnostic.validate_output(output)
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
               Fake.generate(nil, %{
                 input: %{},
                 contextual?: false,
                 context_policy: nil,
                 provider_options: options
               })

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
                   context_policy: nil,
                   provider_options: %{response_schema: schema}
                 })
      end
    end
  end

  # Single builder for the envelope execution actually emits, so a test can only
  # deviate from it deliberately through opts.
  defp contextual_input(request, opts \\ []) do
    context = %{
      "version" => "storyarn-context-v1",
      "scope" => Keyword.get(opts, :scope, "sheet"),
      "entities" => []
    }

    %{"request" => request, "context" => Map.drop(context, Keyword.get(opts, :omit, []))}
  end

  defp generate(input, contextual?) do
    Fake.generate(nil, %{
      input: input,
      contextual?: contextual?,
      context_policy: if(contextual?, do: context_policy()),
      provider_options: %{scenario: :success}
    })
  end

  defp context_policy do
    {:ok, policy} =
      Policy.new(
        %{
          scope: :sheet,
          max_depth: 0,
          max_fan_out: 10,
          max_entities: 20,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        },
        ContextContract
      )

    policy
  end
end
