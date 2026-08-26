defmodule Storyarn.Platform.CommandPalette.Queries do
  @moduledoc false

  alias Storyarn.Platform.CommandPalette.Definition
  alias Storyarn.Platform.CommandPalette.Registry

  @type parameter_completion :: %{
          required(:mode) => Definition.completion_mode(),
          required(:source) => Definition.completion_source()
        }

  @spec operation_catalog() :: [map()]
  def operation_catalog, do: Registry.catalog()

  @spec parameter_completion(String.t(), String.t()) :: {:ok, parameter_completion()} | :error
  def parameter_completion(operation_id, parameter_id) do
    with {:ok, parameter} <- Registry.fetch_parameter(operation_id, parameter_id) do
      {:ok, %{mode: parameter.completion_mode, source: parameter.completion_source}}
    end
  end

  @spec registered_operation_id?(term()) :: boolean()
  def registered_operation_id?(operation_id) do
    match?({:ok, _definition}, Registry.fetch(operation_id))
  end
end
