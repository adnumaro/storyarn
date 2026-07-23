defmodule Storyarn.AI.ResolvedCredential do
  @moduledoc "Ephemeral provider credential; never persisted or placed in a job payload."

  @derive {Inspect, except: [:value]}
  @enforce_keys [:kind, :value]
  defstruct [:kind, :value, metadata: %{}]

  @type t :: %__MODULE__{kind: atom(), value: term(), metadata: map()}
end
