defmodule Storyarn.InvalidSnapshotResetRepo do
  @moduledoc false

  def query(_statement, _params), do: {:ok, %{rows: [["invalid"]]}}
end
