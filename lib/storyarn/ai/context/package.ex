defmodule Storyarn.AI.Context.Package do
  @moduledoc "Versioned deterministic context payload plus its content-free manifest."

  @enforce_keys [
    :version,
    :context_version,
    :scope,
    :payload,
    :manifest,
    :serialized_bytes,
    :hash,
    :warnings
  ]
  defstruct [
    :version,
    :context_version,
    :scope,
    :payload,
    :manifest,
    :serialized_bytes,
    :token_count,
    :hash,
    :warnings
  ]

  @type t :: %__MODULE__{}

  @spec disclosure(t()) :: map()
  def disclosure(%__MODULE__{} = package) do
    %{
      version: package.version,
      context_version: package.context_version,
      scope: Atom.to_string(package.scope),
      serialized_bytes: package.serialized_bytes,
      token_count: package.token_count,
      included_count: length(package.manifest.included),
      excluded_count: length(package.manifest.excluded),
      truncated: "optional_context_truncated" in package.warnings,
      warnings: package.warnings
    }
  end

  @doc "Returns content-free provenance suitable for a route option, operation, or result."
  @spec provenance(t()) :: map()
  def provenance(%__MODULE__{} = package) do
    %{
      "version" => package.version,
      "context_version" => package.context_version,
      "scope" => Atom.to_string(package.scope),
      "serialized_bytes" => package.serialized_bytes,
      "token_count" => package.token_count,
      "warnings" => package.warnings,
      "included" => package.manifest.included,
      "excluded" => package.manifest.excluded
    }
  end
end
