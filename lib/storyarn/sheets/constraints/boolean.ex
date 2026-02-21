defmodule Storyarn.Sheets.Constraints.Boolean do
  @moduledoc """
  Constraints for boolean blocks/columns: mode.

  Mode determines whether the boolean is two-state (true/false) or
  tri-state (true/nil/false). No value clamping is needed — the mode
  is metadata used by the UI and evaluator to know if nil is valid.
  """

  @doc """
  Extracts boolean constraints from a config map.

  Returns a constraints map with the mode, or nil if not set.

      iex> extract(%{"mode" => "tri_state"})
      %{"mode" => "tri_state"}

      iex> extract(%{"mode" => "two_state"})
      nil
  """
  @spec extract(map()) :: map() | nil
  def extract(config) when is_map(config) do
    mode = config["mode"]

    # two_state is the default — only emit constraints when mode differs
    if mode != nil and mode != "two_state" do
      %{"mode" => mode}
    else
      nil
    end
  end

  def extract(_), do: nil

  @doc """
  Clamps a boolean value according to the mode constraint.

  In two-state mode, nil values become false.
  In tri-state mode, nil is a valid value and passes through.

      iex> clamp(nil, %{"mode" => "two_state"})
      false

      iex> clamp(nil, %{"mode" => "tri_state"})
      nil

      iex> clamp(true, nil)
      true
  """
  @spec clamp(any(), map() | nil) :: any()
  def clamp(nil, nil), do: false
  def clamp(nil, %{"mode" => "tri_state"}), do: nil
  def clamp(nil, _), do: false
  def clamp(value, _), do: value
end
