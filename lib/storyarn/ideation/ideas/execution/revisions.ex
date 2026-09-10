defmodule Storyarn.Ideation.Ideas.Execution.Revisions do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def insert(idea, content, actor_id) do
    Repo.insert!(%Revision{
      idea_id: idea.id,
      number: idea.revision,
      actor_id: actor_id,
      title: content.title,
      body: content.body,
      state: content.state
    })
  end

  def record_edit(idea, access, key, fingerprint, base, outcome, content \\ nil) do
    Repo.insert!(%Edit{
      idea_id: idea.id,
      actor_id: access.user_id,
      request_key: key,
      fingerprint: fingerprint,
      base_revision: base,
      result_revision: idea.revision,
      outcome: outcome,
      title: content && content.title,
      body: content && content.body,
      state: content && content.state
    })
  end

  def replay(edit, fingerprint, idea, actor_id) do
    cond do
      edit.fingerprint != fingerprint ->
        {:error, :idempotency_conflict}

      edit.outcome == :conflict ->
        Transaction.conflict(View.edit(edit))

      true ->
        revision = Repo.get_by!(Revision, idea_id: idea.id, number: edit.result_revision)
        Transaction.success(View.idea(idea, revision, actor_id, false, Visible.visible_links(idea, actor_id)))
    end
  end
end
