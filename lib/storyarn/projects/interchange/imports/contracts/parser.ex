defmodule Storyarn.Projects.Imports.Parser do
  @moduledoc """
  Contract implemented by external project format parsers.

  Each parser owns the input profile for its external format. `open_source/2`
  configures the format-neutral secure source opener, while `parse/1` turns the
  resulting validated bundle into an import plan. Neither callback may write to
  the database, storage, logs, or error trackers. This separation keeps preview
  safe and makes parser failures easy to redact.
  """

  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.SourceBundle

  @callback format() :: atom()
  @callback parser_version() :: String.t()
  @callback open_source(String.t(), binary()) ::
              {:ok, SourceBundle.t()} | {:error, atom() | tuple()}
  @callback parse(SourceBundle.t()) :: {:ok, ImportPlan.t()} | {:error, atom() | tuple()}
end
