defmodule Storyarn.Projects.Versioning.Builders.FlowBuilderRollbackTest do
  # ALTER TABLE holds a lock until the sandbox transaction rolls back; keep this
  # case out of the concurrent database suites.
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Versioning.Builders.FlowBuilder
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  setup do
    user = user_fixture(%{email: "flow-builder-#{Ecto.UUID.generate()}@example.com"})
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "instantiate_snapshot/3" do
    test "rolls back and compensates copied assets when transactional localization raises", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "post-commit.mp3", "post-commit audio", "audio/mpeg")

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio.id}
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      _language = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})
      constraint_name = "localized_texts_post_commit_#{System.unique_integer([:positive])}"
      copied_asset_paths_before = stored_asset_paths(target_project.id, audio.filename)

      copied_blob_key =
        BlobStore.blob_key(
          target_project.id,
          audio.blob_hash,
          BlobStore.ext_from_content_type(audio.content_type)
        )

      on_exit(fn -> Assets.storage_delete(copied_blob_key) end)

      Repo.query!(
        "ALTER TABLE localized_texts ADD CONSTRAINT #{constraint_name} " <>
          "CHECK (project_id <> #{target_project.id})"
      )

      assert_raise Postgrex.Error, ~r/#{constraint_name}/, fn ->
        FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
          asset_mode: :copy,
          user_id: user.id,
          reset_shortcut: true
        )
      end

      refute Repo.exists?(from flow in Flow, where: flow.project_id == ^target_project.id)
      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^target_project.id)
      assert stored_asset_paths(target_project.id, audio.filename) == copied_asset_paths_before
      assert {:ok, "post-commit audio"} = Assets.storage_download(copied_blob_key)
      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
    end
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(
        BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type))
      )
    end)

    asset
  end

  defp stored_asset_paths(project_id, filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/#{project_id}/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
