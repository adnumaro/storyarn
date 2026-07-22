defmodule Storyarn.AI.TaskDefinition do
  @moduledoc "Behaviour implemented by every registered AI task."

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation

  @callback definition() :: map()
  @callback validate_input(map() | list()) :: :ok | {:error, atom()}
  @callback validate_output(term()) :: :ok | {:error, atom()}
  @callback authorize_subject(Scope.t(), ExecutionIntent.t() | Operation.t(), :execute | :apply | :attach) ::
              :ok | {:error, atom()}
  @callback subject_current?(Operation.t()) :: boolean()

  @optional_callbacks validate_input: 1, validate_output: 1, authorize_subject: 3, subject_current?: 1
end
