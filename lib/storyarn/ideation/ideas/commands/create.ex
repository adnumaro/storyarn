defmodule Storyarn.Ideation.Ideas.Commands.Create do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Execution.Publication
  alias Storyarn.Ideation.Ideas.Execution.Revisions
  alias Storyarn.Ideation.Ideas.Execution.Transaction
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Canvas
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run_canvas(scope, project_id, session_id, attrs) when is_map(attrs),
    do: run(scope, project_id, session_id, Map.put(attrs, :canvas_contribution, true))

  def run_canvas(_, _, _, _), do: {:error, :invalid_idea}

  def run(scope, project_id, session_id, attrs), do: create(scope, project_id, session_id, attrs)

  defp create(scope, project_id, session_id, attrs) when is_map(attrs) do
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

      Transaction.run(scope, project_id, session_id, &create_locked(&1, key, fields, attrs))
    end
  end

  defp create(_scope, _project_id, _session_id, _attrs), do: {:error, :invalid_idea}

  defp create_locked(access, key, fields, attrs) do
    case Repo.get_by(Idea, session_id: access.session_id, author_id: access.user_id, creation_key: key) do
      nil ->
        insert(access, key, Input.fingerprint({:create, nil, fields}), attrs)

      idea ->
        edit = Repo.get_by!(Edit, idea_id: idea.id, actor_id: access.user_id, request_key: key)

        fingerprint = Input.fingerprint({:create, nil, fields})
        Revisions.replay(edit, fingerprint, idea, access.user_id)
    end
  end

  defp insert(access, key, fingerprint, attrs) do
    with {:ok, policy} <- Policy.contribution_policy(access, attrs),
         {:ok, canvas} <- initial_canvas(Input.get(attrs, :canvas)),
         changeset = Revision.changeset(%Revision{}, Input.content_attrs(attrs)),
         true <- changeset.valid? || {:error, changeset} do
      content = apply_changes(changeset)

      idea =
        Repo.insert!(
          struct!(
            Idea,
            %{
              canvas: canvas,
              session_id: access.session_id,
              author_id: access.user_id,
              author_kind: :human,
              creation_key: key,
              state: content.state,
              publication_consent: policy.consent,
              configuration_version: access.configuration_version
            }
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
end
