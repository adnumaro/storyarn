defmodule Storyarn.AI.TaskRegistry do
  @moduledoc """
  Canonical registry for AI task contracts and their content-free palette ids.

  Production starts with an empty task list. Functional slices add explicit
  task modules; arbitrary caller-supplied task definitions are never accepted.
  """

  alias Storyarn.AI.Task

  @spec all() :: [Task.t()]
  def all do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:tasks, [])
    |> Enum.map(&load_task!/1)
    |> ensure_unique_ids!()
  end

  @spec fetch(String.t()) :: {:ok, Task.t()} | {:error, :unknown_task | :task_disabled}
  def fetch(task_id) when is_binary(task_id) do
    case get(task_id) do
      {:error, :unknown_task} -> {:error, :unknown_task}
      {:ok, task} -> if Task.enabled?(task), do: {:ok, task}, else: {:error, :task_disabled}
    end
  end

  def fetch(_task_id), do: {:error, :unknown_task}

  @doc false
  @spec get(String.t()) :: {:ok, Task.t()} | {:error, :unknown_task}
  def get(task_id) when is_binary(task_id) do
    case Enum.find(all(), &(&1.id == task_id)) do
      nil -> {:error, :unknown_task}
      task -> {:ok, task}
    end
  end

  def get(_task_id), do: {:error, :unknown_task}

  @spec command_id?(String.t()) :: boolean()
  def command_id?(command_id) when is_binary(command_id) do
    Enum.any?(all(), &(command_id in &1.command_ids))
  end

  def command_id?(_command_id), do: false

  defp load_task!(module) when is_atom(module) do
    if !Code.ensure_loaded?(module) or !function_exported?(module, :definition, 0) do
      raise ArgumentError, "AI task #{inspect(module)} does not implement definition/0"
    end

    case Task.new(module, module.definition()) do
      {:ok, task} -> task
      {:error, errors} -> raise ArgumentError, "invalid AI task #{inspect(module)}: #{inspect(Enum.reverse(errors))}"
    end
  end

  defp ensure_unique_ids!(tasks) do
    ids = Enum.map(tasks, & &1.id)
    command_ids = Enum.flat_map(tasks, & &1.command_ids)

    if Enum.uniq(ids) != ids, do: raise(ArgumentError, "duplicate AI task id")
    if Enum.uniq(command_ids) != command_ids, do: raise(ArgumentError, "duplicate AI palette command id")

    tasks
  end
end
