defmodule Storyarn.Ideation.Ideas.View do
  @moduledoc "Authorized idea projections. Raw persistence schemas must not be sent to clients."
  alias Storyarn.Ideation.Ideas.Rules.Policy

  def idea(idea, revision, actor_id, source_published? \\ false, visible_links \\ []) do
    source_visible? = Policy.author?(idea, actor_id) or source_published?

    public = %{
      deleted_at: idea.deleted_at,
      canvas: canvas(idea.canvas, visible_links),
      id: idea.id,
      session_id: idea.session_id,
      round_id: idea.round_id,
      late_contribution: idea.late_contribution,
      author_id: idea.author_id,
      author_kind: idea.author_kind,
      title: revision.title,
      body: revision.body,
      revision: revision.number,
      state: idea.state,
      visibility: if(is_nil(idea.published_revision), do: :private, else: :shared),
      published_revision: idea.published_revision,
      source_idea_id: if(source_visible?, do: idea.source_idea_id),
      source_revision: if(source_visible?, do: idea.source_revision),
      inserted_at: idea.inserted_at
    }

    if Policy.author?(idea, actor_id) do
      Map.merge(public, %{
        current_revision: idea.revision,
        publication_consent: idea.publication_consent,
        configuration_version: idea.configuration_version,
        has_unpublished_changes: idea.revision != idea.published_revision
      })
    else
      public
    end
  end

  def canvas(canvas, visible_links) do
    canvas
    |> Map.drop(["request_key", "links_receipt", "creation_links_receipt"])
    |> Map.put_new("links_version", 0)
    |> Map.put("links", visible_links)
    |> filter_directions(visible_links)
  end

  defp filter_directions(canvas, visible_links) do
    if Map.has_key?(canvas, "link_directions"),
      do: Map.update!(canvas, "link_directions", &Map.take(&1, Enum.map(visible_links, fn id -> to_string(id) end))),
      else: canvas
  end

  def edit(edit) do
    receipt = Map.take(edit, [:id, :idea_id, :request_key, :outcome, :base_revision, :result_revision, :inserted_at])

    if edit.outcome == :conflict,
      do: Map.put(receipt, :attempted, Map.take(edit, [:title, :body, :state])),
      else: receipt
  end

  def reveal(operation) do
    Map.take(operation, [:id, :session_id, :request_key, :manifest, :status, :inserted_at, :completed_at])
  end
end
