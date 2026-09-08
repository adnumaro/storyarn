defmodule Storyarn.Ideation.Ideas.Rules.Policy do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Rules.Input

  def manager?(access), do: access.owner? or access.facilitator_id == access.user_id
  def author?(idea, actor_id), do: not is_nil(idea.author_id) and idea.author_id == actor_id

  def can_publish?(idea, access) do
    author?(idea, access.user_id) or
      (not is_nil(idea.author_id) and manager?(access) and idea.publication_consent == :facilitator_assisted)
  end

  def contribution_policy(access, %{canvas_contribution: true}) do
    {:ok, %{consent: :facilitator_assisted, shared?: access.configuration.private_mode != true}}
  end

  def contribution_policy(access, attrs) do
    consent = provided_or(attrs, :publication_consent, :author_only)
    visibility = provided_or(attrs, :visibility, access.configuration.default_visibility)

    cond do
      Input.get(attrs, :configuration_version) != access.configuration_version ->
        {:error, :stale_configuration}

      consent not in [:author_only, "author_only", :facilitator_assisted, "facilitator_assisted"] ->
        {:error, :invalid_publication_consent}

      consent in [:facilitator_assisted, "facilitator_assisted"] and
          access.configuration.publication_policy != :facilitator_assisted ->
        {:error, :invalid_publication_consent}

      visibility not in [:private, "private", :shared, "shared"] ->
        {:error, :invalid_visibility}

      true ->
        {:ok,
         %{
           consent: if(consent in [:author_only, "author_only"], do: :author_only, else: :facilitator_assisted),
           shared?: visibility in [:shared, "shared"]
         }}
    end
  end

  defp provided_or(attrs, key, default) do
    if Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key)),
      do: Input.get(attrs, key),
      else: default
  end
end
