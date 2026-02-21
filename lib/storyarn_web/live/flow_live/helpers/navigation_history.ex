defmodule StoryarnWeb.FlowLive.Helpers.NavigationHistory do
  @moduledoc """
  Pure functional navigation history stack for the flow editor.

  Stores a list of visited flows and a cursor index. Supports push,
  back, and forward operations. Maximum 20 entries.
  """

  @max_entries 20

  @type entry :: %{flow_id: integer(), flow_name: String.t()}
  @type t :: %{entries: [entry()], index: non_neg_integer()}

  @doc """
  Creates a new history with the initial flow as the only entry.
  """
  @spec new(integer(), String.t()) :: t()
  def new(flow_id, flow_name) do
    %{
      entries: [%{flow_id: flow_id, flow_name: flow_name}],
      index: 0
    }
  end

  @doc """
  Push a new flow onto the history.

  If the cursor is not at the end (i.e., user went back), the forward
  entries are discarded (same as browser navigation). The list is
  truncated to #{@max_entries} from the front if it exceeds the limit.
  """
  @spec push(t(), integer(), String.t()) :: t()
  def push(history, flow_id, flow_name) do
    current = Enum.at(history.entries, history.index)

    if current && current.flow_id == flow_id do
      history
    else
      # Discard forward entries
      entries = Enum.take(history.entries, history.index + 1)
      new_entry = %{flow_id: flow_id, flow_name: flow_name}
      entries = entries ++ [new_entry]

      # Truncate from the front if too long
      entries =
        if length(entries) > @max_entries do
          Enum.drop(entries, length(entries) - @max_entries)
        else
          entries
        end

      %{entries: entries, index: length(entries) - 1}
    end
  end

  @doc """
  Move back one entry. Returns `{:ok, entry, updated_history}` or `:at_start`.
  """
  @spec back(t()) :: {:ok, entry(), t()} | :at_start
  def back(%{index: 0}), do: :at_start

  def back(%{entries: entries, index: index} = history) do
    new_index = index - 1
    entry = Enum.at(entries, new_index)
    {:ok, entry, %{history | index: new_index}}
  end

  @doc """
  Move forward one entry. Returns `{:ok, entry, updated_history}` or `:at_end`.
  """
  @spec forward(t()) :: {:ok, entry(), t()} | :at_end
  def forward(%{entries: entries, index: index}) when index >= length(entries) - 1 do
    :at_end
  end

  def forward(%{entries: entries, index: index} = history) do
    new_index = index + 1
    entry = Enum.at(entries, new_index)
    {:ok, entry, %{history | index: new_index}}
  end

  @doc """
  Returns true if back navigation is possible.
  """
  @spec can_go_back?(t()) :: boolean()
  def can_go_back?(%{index: 0}), do: false
  def can_go_back?(_), do: true

  @doc """
  Returns true if forward navigation is possible.
  """
  @spec can_go_forward?(t()) :: boolean()
  def can_go_forward?(%{entries: entries, index: index}) do
    index < length(entries) - 1
  end

  @doc """
  Returns the previous entry without moving the cursor, or `nil` if at start.
  """
  @spec peek_back(t()) :: entry() | nil
  def peek_back(%{index: 0}), do: nil
  def peek_back(%{entries: entries, index: index}), do: Enum.at(entries, index - 1)

  @doc """
  Returns the next entry without moving the cursor, or `nil` if at end.
  """
  @spec peek_forward(t()) :: entry() | nil
  def peek_forward(%{entries: entries, index: index}) do
    if index < length(entries) - 1, do: Enum.at(entries, index + 1)
  end

  @doc """
  Returns the current entry.
  """
  @spec current(t()) :: entry()
  def current(%{entries: entries, index: index}) do
    Enum.at(entries, index)
  end
end
