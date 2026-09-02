defmodule Storyarn.Projects.Imports.MainFlowPolicy do
  @moduledoc """
  Resolves the single-main-flow invariant for project imports.

  Source adapters may nominate a flow by setting `is_main`, but the target
  project decides whether that nomination can be applied. The decision is made
  again while the project row is locked, so a preview is informative rather
  than authoritative.
  """

  @type existing_main :: nil | %{required(:shortcut) => String.t() | nil}
  @type state :: %{required(:main_claimed?) => boolean()}

  @doc "Returns the materialization state for the target project's active main flow."
  @spec initial_state(existing_main()) :: state()
  def initial_state(nil), do: %{main_claimed?: false}
  def initial_state(%{shortcut: _shortcut}), do: %{main_claimed?: true}

  @doc """
  Decides whether one resolved imported flow must be persisted as main.

  An adapter nomination is accepted only when the project has no active main
  flow and no earlier imported flow has claimed the role. Conflicting
  overwrites are rejected before this function because replacing a root
  identity without relinking all references is not supported.
  """
  @spec resolve(map(), String.t() | nil, atom(), state()) :: {boolean(), state()}
  def resolve(flow_data, _resolved_shortcut, _strategy, state) do
    cond do
      state.main_claimed? ->
        {false, state}

      flow_data["is_main"] == true ->
        {true, %{state | main_claimed?: true}}

      true ->
        {false, state}
    end
  end

  @doc """
  Builds every user-selectable preview outcome from current target facts.

  Returning the complete matrix lets the UI react immediately when the user
  changes mode or conflict strategy. Materialization still recalculates the
  decision under the project lock.
  """
  @spec preview([map()], existing_main(), [String.t()]) :: map()
  def preview(flows, existing_main, conflicting_shortcuts) do
    candidates = Enum.filter(flows, &(&1["is_main"] == true))
    conflict_set = MapSet.new(conflicting_shortcuts)
    target_has_main? = not is_nil(existing_main)
    candidate_exists? = candidates != []

    candidate_survives_skip? =
      Enum.any?(candidates, fn candidate ->
        not MapSet.member?(conflict_set, candidate["shortcut"])
      end)

    %{
      additive: %{
        skip: additive_outcome(target_has_main?, candidate_survives_skip?),
        overwrite: additive_outcome(target_has_main?, candidate_survives_skip?),
        rename: additive_outcome(target_has_main?, candidate_exists?)
      },
      replace_project: if(candidate_exists?, do: "import_candidate", else: "none")
    }
  end

  defp additive_outcome(true, _candidate_available?), do: "preserve_existing"
  defp additive_outcome(false, true), do: "import_candidate"
  defp additive_outcome(false, false), do: "none"
end
