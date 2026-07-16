defmodule Storyarn.Imports.Parser do
  @moduledoc """
  Contract implemented by external project format parsers.

  Parsers are pure: they receive an already validated source bundle and return
  an import plan. They must not write to the database, storage, logs, or error
  trackers. This separation keeps preview safe and makes parser failures easy
  to redact.
  """

  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.SourceBundle

  @callback format() :: atom()
  @callback parser_version() :: String.t()
  @callback parse(SourceBundle.t()) :: {:ok, ImportPlan.t()} | {:error, atom() | tuple()}
end
