defmodule Storyarn.Ideation.Ideas.Commands.Create do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Revisions
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run_canvas(scope, project_id, session_id, attrs) when is_map(attrs),
    do: run(scope, project_id, session_id, Map.put(attrs, :canvas_contribution, true))

  def run_canvas(_, _, _, _), do: {:error, :invalid_idea}

  def derive_canvas(scope, project_id, session_id, id, revision, attrs) when is_map(attrs),
    do: derive(scope, project_id, session_id, id, revision, Map.put(attrs, :canvas_contribution, true))

  def derive_canvas(_, _, _, _, _, _), do: {:error, :invalid_idea}

  def run(scope, project_id, session_id, attrs), do: create(scope, project_id, session_id, nil, attrs)

  def derive(scope, project_id, session_id, source_id, source_revision, attrs),
    do: create(scope, project_id, session_id, {source_id, source_revision}, attrs)

  defp create(scope, project_id, session_id, source, attrs) when is_map(attrs) do
    with {:ok, key} <- Input.request_key(attrs) do
      fields =
        for field <- [
              :title,
              :body,
              :state,
              :configuration_version,
              :publication_consent,
              :visibility,
              :canvas,
              :canvas_contribution
            ],
            Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
            do: {field, Input.get(attrs, field)}

      Transaction.run(scope, project_id, session_id, &create_locked(&1, key, fields, source, attrs))
    end
  end

  defp create(_scope, _project_id, _session_id, _source, _attrs), do: {:error, :invalid_idea}

  defp create_locked(access, key, fields, source, attrs) do
    case Repo.get_by(Idea, session_id: access.session_id, author_id: access.user_id, creation_key: key) do
      nil ->
        insert(access, key, Input.fingerprint({:create, source, fields}), source, attrs)

      idea ->
        edit = Repo.get_by!(Edit, idea_id: idea.id, actor_id: access.user_id, request_key: key)

        with {:ok, request_source} <- creation_request_source(idea, source) do
          fingerprint = Input.fingerprint({:create, request_source, fields})
          Revisions.replay(edit, fingerprint, idea, access.user_id)
        end
    end
  end

  defp insert(access, key, fingerprint, source, attrs) do
    with {:ok, policy} <- Policy.contribution_policy(access, attrs),
         {:ok, canvas} <- initial_canvas(Input.get(attrs, :canvas)),
         {:ok, source_fields, content_attrs} <- source_content(source, access, attrs),
         changeset = Revision.changeset(%Revision{}, content_attrs),
         true <- changeset.valid? || {:error, changeset} do
      content = apply_changes(changeset)

      idea =
        Repo.insert!(
          struct!(
            Idea,
            Map.merge(source_fields, %{
              canvas: canvas,
              session_id: access.session_id,
              author_id: access.user_id,
              author_kind: :human,
              creation_key: key,
              state: content.state,
              publication_consent: policy.consent,
              configuration_version: access.configuration_version
            })
          )
        )

      revision = Revisions.insert(idea, content, access.user_id)
      Revisions.record_edit(idea, access, key, fingerprint, 0, :saved)
      idea = if policy.shared?, do: Publication.publish_creation(idea, access.user_id), else: idea
      audiences = if policy.shared?, do: [:shared], else: [access.user_id]
      Transaction.success(View.idea(idea, revision, access.user_id), audiences)
    end
  end

  defp initial_canvas(nil), do: {:ok, %{}}
  defp initial_canvas(attrs), do: Canvas.normalize(attrs)

  defp source_content(nil, _access, attrs), do: {:ok, %{}, Input.content_attrs(attrs)}

  defp source_content({source_id, number}, access, attrs) do
    with {:ok, source, revision} <- Visible.readable_revision(access.session_id, source_id, number, access.user_id) do
      fields = %{source_idea_id: source.id, creation_source_id: source.id, source_revision: revision.number}
      content = Map.merge(%{title: revision.title, body: revision.body}, Input.content_attrs(attrs))
      {:ok, fields, content}
    end
  end

  defp creation_request_source(%{creation_source_id: nil}, nil), do: {:ok, nil}

  defp creation_request_source(
         %{source_idea_id: id, source_revision: number, creation_source_id: original},
         {id, number}
       ), do: {:ok, {original, number}}

  defp creation_request_source(_, _), do: {:error, :idempotency_conflict}
end
