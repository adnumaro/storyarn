defmodule Storyarn.AI.Context.PersistenceContract do
  @moduledoc false

  @persisted_scopes ~w(dialogue flow_neighborhood sheet)
  @nonpersisted_scope "structural_finding"

  @spec valid?(String.t() | nil, map() | nil, map() | nil) :: boolean()
  def valid?(nil, nil, nil), do: true

  def valid?(hash, manifest, subject) when is_binary(hash) and is_map(manifest) do
    valid_subject?(context_scope(manifest), subject)
  end

  def valid?(_hash, _manifest, _subject), do: false

  defp valid_subject?(scope, subject) when scope in @persisted_scopes, do: is_map(subject)
  defp valid_subject?(@nonpersisted_scope, subject), do: is_nil(subject)
  defp valid_subject?(_scope, _subject), do: false

  defp context_scope(manifest), do: Map.get(manifest, "scope", Map.get(manifest, :scope))
end
