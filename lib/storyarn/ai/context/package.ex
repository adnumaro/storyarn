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
      excluded_count: excluded_count(package),
      truncated: "optional_context_truncated" in package.warnings,
      warnings: package.warnings
    }
  end

  @doc "Counts omitted entities, expanding bounded overflow summaries."
  @spec excluded_count(t()) :: non_neg_integer()
  def excluded_count(%__MODULE__{manifest: %{excluded: excluded}}) when is_list(excluded) do
    Enum.reduce(excluded, 0, fn
      %{"omitted_count" => count}, acc when is_integer(count) and count > 0 ->
        acc + count

      _excluded_item, acc ->
        acc + 1
    end)
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
