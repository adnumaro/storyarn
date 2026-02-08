defmodule Storyarn.Flows.Evaluator.State do
  @moduledoc """
  Debug session state for the flow evaluator.

  An ephemeral, in-memory struct (stored in socket assigns) that tracks
  the full execution state of a debug session: current node, variable
  state with change tracking, execution path, console messages, and
  snapshots for undo capability.

  Sessions are not persisted. Closing the debug panel discards all state.
  """

  @type status :: :paused | :running | :waiting_input | :finished

  @type variable :: %{
          value: any(),
          initial_value: any(),
          previous_value: any(),
          source: :initial | :user_override | :instruction,
          block_type: String.t(),
          block_id: integer(),
          sheet_shortcut: String.t(),
          variable_name: String.t()
        }

  @type console_entry :: %{
          ts: integer(),
          level: :info | :warning | :error,
          node_id: integer() | nil,
          node_label: String.t(),
          message: String.t(),
          rule_details: [map()] | nil
        }

  @type history_entry :: %{
          ts: integer(),
          node_id: integer() | nil,
          node_label: String.t(),
          variable_ref: String.t(),
          old_value: any(),
          new_value: any(),
          source: :instruction | :user_override
        }

  @type snapshot :: %{
          node_id: integer(),
          variables: %{String.t() => variable()},
          execution_path: [integer()],
          pending_choices: map() | nil,
          status: status(),
          history: [history_entry()]
        }

  @type t :: %__MODULE__{
          start_node_id: integer() | nil,
          current_node_id: integer() | nil,
          status: status(),
          variables: %{String.t() => variable()},
          initial_variables: %{String.t() => variable()},
          previous_variables: %{String.t() => variable()},
          snapshots: [snapshot()],
          history: [history_entry()],
          console: [console_entry()],
          execution_path: [integer()],
          pending_choices: map() | nil,
          step_count: non_neg_integer(),
          max_steps: non_neg_integer(),
          started_at: integer() | nil
        }

  defstruct [
    :start_node_id,
    :current_node_id,
    :started_at,
    status: :paused,
    variables: %{},
    initial_variables: %{},
    previous_variables: %{},
    snapshots: [],
    history: [],
    console: [],
    execution_path: [],
    pending_choices: nil,
    step_count: 0,
    max_steps: 500
  ]
end
