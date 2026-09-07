defmodule Storyarn.Ideation.Ideas.Commands.Update do
  @moduledoc false
  import Ecto.Changeset
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_revision: 1]

  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Revisions
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run_canvas(scope, project_id, session_id, idea_id, revision, attrs) when is_map(attrs),
    do: run(scope, project_id, session_id, idea_id, revision, Map.put(attrs, :canvas_contribution, true))

  def run_canvas(_, _, _, _, _, _), do: {:error, :invalid_edit}

  def run(scope, project_id, session_id, idea_id, expected_revision, attrs)
      when valid_revision(expected_revision) and is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs) do
      fingerprint = Input.fingerprint({:update, expected_revision, normalized_attrs(attrs)})

      Transaction.run(
        scope,
        project_id,
        session_id,
        &update_locked(&1, idea_id, key, fingerprint, expected_revision, attrs)
      )
    end
  end

  def run(_scope, _project_id, _session_id, _idea_id, _revision, _attrs), do: {:error, :invalid_edit}

  defp update_locked(access, idea_id, key, fingerprint, expected_revision, attrs) do
    with {:ok, idea} <- Visible.owned(access.session_id, idea_id, access.user_id) do
      case Repo.get_by(Edit, idea_id: idea.id, actor_id: access.user_id, request_key: key) do
        nil -> save(idea, access, key, fingerprint, expected_revision, attrs)
        edit -> Revisions.replay(edit, fingerprint, idea, access.user_id)
      end
    end
  end

  defp save(idea, access, key, fingerprint, expected, attrs) do
    current = Repo.get_by!(Revision, idea_id: idea.id, number: idea.revision)
    changeset = Revision.changeset(current, Input.content_attrs(attrs))

    cond do
      not changeset.valid? ->
        {:error, changeset}

      idea.revision != expected ->
        conflict = Revisions.record_edit(idea, access, key, fingerprint, expected, :conflict, apply_changes(changeset))
        Transaction.conflict(View.edit(conflict))

      changeset.changes == %{} ->
        Revisions.record_edit(idea, access, key, fingerprint, expected, :saved)
        Transaction.success(View.idea(idea, current, access.user_id))

      true ->
        content = apply_changes(changeset)
        updated = idea |> change(revision: idea.revision + 1, state: content.state) |> Repo.update!()
        revision = Revisions.insert(updated, content, access.user_id)
        Revisions.record_edit(updated, access, key, fingerprint, expected, :saved)
        publish? = Input.get(attrs, :canvas_contribution) == true and access.configuration.private_mode != true
        updated = if publish?, do: Publication.publish_creation(updated, access.user_id), else: updated

        Transaction.success(
          View.idea(updated, revision, access.user_id),
          audiences(idea, updated, publish?, access.user_id)
        )
    end
  end

  defp audiences(idea, updated, publish?, actor_id) do
    if publish? or (idea.published_revision && idea.state != updated.state),
      do: [:shared, actor_id],
      else: [actor_id]
  end

  # Preserve presence as well as value: an omitted field differs from clearing it.
  defp normalized_attrs(attrs) do
    for field <- [:title, :body, :state, :canvas_contribution],
        Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
        do: {field, Input.get(attrs, field)}
  end
end
