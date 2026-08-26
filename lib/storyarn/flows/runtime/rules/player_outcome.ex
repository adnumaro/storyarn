defmodule Storyarn.Flows.PlayerOutcome do
  @moduledoc """
  Builds the Flow-owned semantic outcome of a completed player run.

  Presentation adapters may provide localized fallback copy when `:label` is
  nil; authored labels, tags, colors and run statistics are owned here.
  """

  alias Storyarn.Flows.Evaluator.Helpers

  @type t :: %{
          label: String.t() | nil,
          outcome_color: String.t() | nil,
          outcome_tags: [String.t()],
          step_count: non_neg_integer(),
          variables_changed: non_neg_integer(),
          choices_made: non_neg_integer(),
          node_id: integer()
        }

  @doc "Builds authored outcome metadata and evaluator run statistics."
  @spec build(map(), map()) :: t()
  def build(%{id: node_id} = node, state) do
    data = node.data || %{}

    %{
      label: data["label"] || Helpers.strip_html(data["text"]),
      outcome_color: data["outcome_color"],
      outcome_tags: data["outcome_tags"] || [],
      step_count: state.step_count,
      variables_changed: changed_variable_count(state.variables),
      choices_made: choice_count(state.console),
      node_id: node_id
    }
  end

  defp changed_variable_count(variables) do
    Enum.count(variables, fn
      {_key, %{value: value, initial_value: initial_value}} -> value != initial_value
      _invalid_variable -> false
    end)
  end

  defp choice_count(console) do
    Enum.count(console, fn
      %{message: message} when is_binary(message) -> String.starts_with?(message, "Selected:")
      _invalid_entry -> false
    end)
  end
end
