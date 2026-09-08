defmodule Storyarn.Ideation.IdeasTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision

  setup do
    ideation_fixture()
  end

  test "saves a private attributed idea and can resume its exact content", ctx do
    idea = idea_fixture(ctx, %{title: "  The antagonist  ", body: "<p>Wants <strong>peace</strong>.</p>"})
    assert idea.author_id == ctx.author.user.id
    assert idea.author_kind == :human
    assert idea.visibility == :private
    assert idea.state == :active
    assert idea.title == "The antagonist"
    assert idea.revision == 1
    assert idea.has_unpublished_changes
    assert {:ok, ^idea} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert {:ok, [^idea]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)

    assert Repo.get_by!(Revision, idea_id: idea.id, number: 1).body == "<p>Wants <strong>peace</strong>.</p>"
  end

  test "body and title are encrypted in storage and redacted from inspection", ctx do
    idea = idea_fixture(ctx, %{title: "Secret title", body: "<p>Secret motivation</p>"})
    revision = Repo.get_by!(Revision, idea_id: idea.id, number: 1)
    refute inspect(revision) =~ "Secret"
    [[title, body]] = Repo.query!("SELECT title, body FROM ideation_idea_revisions WHERE idea_id = $1", [idea.id]).rows
    assert :binary.match(title, "Secret") == :nomatch
    assert :binary.match(body, "Secret") == :nomatch
    assert revision.body == "<p>Secret motivation</p>"
  end

  test "author identity, visibility pointers and origin cannot be forged in content attributes", ctx do
    idea =
      idea_fixture(ctx, %{
        author_id: ctx.peer.user.id,
        author_kind: :ai,
        revision: 500,
        published_revision: 500,
        source_idea_id: 999,
        source_revision: 4
      })

    assert idea.author_id == ctx.author.user.id
    assert idea.author_kind == :human
    assert idea.revision == 1
    assert idea.published_revision == nil
    assert idea.source_idea_id == nil
  end

  test "rejects invalid bodies without crashing or persisting partial records", ctx do
    for body <- [
          nil,
          "",
          "  ",
          "<p><br></p>",
          <<255>>,
          42,
          %{},
          String.duplicate("x", 64_001),
          "<img src='https://example.com/image.png'>",
          "<p><a href='/private'>Link</a></p>"
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{body: body}))
    end

    assert Repo.aggregate(Idea, :count) == 0
    assert Repo.aggregate(Revision, :count) == 0
    assert Repo.aggregate(Edit, :count) == 0
  end

  test "bounds title and nesting and keeps only safe formatting attributes", ctx do
    assert {:error, changeset} =
             Ideation.create_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea_attrs(%{title: String.duplicate("x", 161)})
             )

    assert errors_on(changeset).title != []

    assert {:error, _} =
             Ideation.create_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea_attrs(%{
                 body: String.duplicate("<blockquote>", 20) <> "text" <> String.duplicate("</blockquote>", 20)
               })
             )

    idea = idea_fixture(ctx, %{body: "<p onclick='steal()' style='color:red' data-secret='x'>Safe <b>text</b></p>"})
    assert idea.body == "<p>Safe <b>text</b></p>"
  end

  test "keeps the space between adjacent inline marks and normalizes it idempotently", ctx do
    idea = idea_fixture(ctx, %{body: "<p><strong>bold</strong> <em>and</em>\t\t<u>more</u> plain\uE000</p>"})
    assert idea.body == "<p><strong>bold</strong> <em>and</em> <u>more</u> plain</p>"

    assert {:ok, %{revision: 1}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: idea.body}))

    for body <- ["<p> </p>", "<p>\t</p>", "<p><strong> </strong></p>"] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{body: body}))
    end
  end

  test "updates preserve immutable revisions and reject blank input on existing content", ctx do
    idea = idea_fixture(ctx)

    for body <- [nil, "", "  ", 42, %{}] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{body: body}))
    end

    assert {:ok, updated} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "<p>Developed idea</p>", title: nil})
             )

    assert updated.revision == 2
    second = Repo.get_by!(Revision, idea_id: idea.id, number: 2)
    first = Repo.get_by!(Revision, idea_id: idea.id, number: 1)
    assert second.body == "<p>Developed idea</p>"
    assert first.body == "<p>Original idea</p>"
  end

  test "no-op saves do not create content revisions and retain a retry receipt", ctx do
    idea = idea_fixture(ctx)
    attrs = edit_attrs(%{body: idea.body})
    assert {:ok, saved} = Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)
    assert saved.revision == 1

    assert %{outcome: :saved, result_revision: 1} =
             Repo.get_by!(Edit, idea_id: idea.id, request_key: attrs.request_key)

    assert Repo.aggregate(Revision, :count) == 1
  end

  test "creation retries retain their result after configuration changes and reject reused keys", ctx do
    attrs = idea_attrs()
    assert {:ok, idea} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    ctx = configure_session(ctx, %{default_visibility: :shared})
    assert {:ok, ^idea} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:error, :idempotency_conflict} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, %{attrs | body: "Different"})

    assert Repo.aggregate(Idea, :count) == 1
  end

  test "save retries do not overwrite later edits and keep the acknowledged revision", ctx do
    idea = idea_fixture(ctx)
    attrs = edit_attrs(%{body: "First save"})
    assert {:ok, second} = Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)

    assert {:ok, third} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               2,
               edit_attrs(%{body: "Later save"})
             )

    assert {:ok, replay} = Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)
    assert replay.body == second.body
    assert replay.revision == 2
    assert replay.current_revision == 3
    assert {:ok, ^third} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)

    assert {:error, :idempotency_conflict} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, %{
               attrs
               | body: "Different request"
             })

    assert Repo.aggregate(Revision, :count) == 3
  end

  test "a stale save durably preserves both alternatives and retrying does not duplicate conflicts", ctx do
    idea = idea_fixture(ctx)

    assert {:ok, winner} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "Winning text"})
             )

    attrs = edit_attrs(%{body: "Unsent alternative"})

    assert {:error, {:edit_conflict, conflict}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)

    assert conflict.base_revision == 1
    assert conflict.result_revision == 2
    assert conflict.attempted.body == "Unsent alternative"

    assert Repo.get_by!(Edit, idea_id: idea.id, request_key: attrs.request_key).id == conflict.id

    assert {:error, {:edit_conflict, ^conflict}} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, attrs)

    assert {:ok, ^winner} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)

    assert {:ok, recovered} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 2, edit_attrs(conflict.attempted))

    assert recovered.body == "Unsent alternative"
    assert recovered.revision == 3
    assert Repo.get!(Edit, conflict.id).body == "Unsent alternative"
  end

  test "creative state stays independent from visibility and can be restored", ctx do
    idea = idea_fixture(ctx)

    assert {:ok, parked} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1, edit_attrs(%{state: :parked}))

    assert parked.visibility == :private
    assert {:ok, []} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, [^parked]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, state: :parked)
    shared = publish_idea(ctx, parked)
    assert shared.state == :parked

    assert {:ok, discarded} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               2,
               edit_attrs(%{state: :discarded})
             )

    assert discarded.visibility == :shared
    assert {:ok, %{discarded: 1, active: 0, parked: 0}} = Ideation.count_ideas(ctx.peer, ctx.project.id, ctx.session.id)

    assert {:ok, restored} =
             Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 3, edit_attrs(%{state: :active}))

    assert restored.visibility == :shared
  end

  test "bounded lists reject malformed filters and cursors", ctx do
    first = idea_fixture(ctx)
    second = idea_fixture(ctx)
    assert {:ok, [^second]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, limit: 1)
    assert {:ok, [^first]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, before_id: second.id)

    for opts <- [
          [limit: 0],
          [limit: 201],
          [before_id: -1],
          [before_id: 9_223_372_036_854_775_808],
          [visibility: :hidden],
          [state: :unknown],
          %{},
          ["invalid"]
        ] do
      assert {:error, :invalid_options} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, opts)
    end
  end

  test "publishing a derivation does not expose its private source identity or revision", ctx do
    source = idea_fixture(ctx)

    # Legacy provenance remains readable even though creating derivatives is no longer public.
    derived = idea_fixture(ctx)

    Idea
    |> Repo.get!(derived.id)
    |> Ecto.Changeset.change(source_idea_id: source.id, creation_source_id: source.id, source_revision: 1)
    |> Repo.update!()

    {:ok, derived} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, derived.id)

    derived = publish_idea(ctx, derived)
    assert derived.source_idea_id == source.id
    assert derived.source_revision == 1

    assert {:ok, visible} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, derived.id)
    assert visible.source_idea_id == nil
    assert visible.source_revision == nil
    assert {:ok, [^visible]} = Ideation.list_ideas(ctx.peer, ctx.project.id, ctx.session.id)

    publish_idea(ctx, source)
    assert {:ok, attributed} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, derived.id)
    assert attributed.source_idea_id == source.id
    assert attributed.source_revision == 1
  end

  test "rejects invalid identities, request keys, configuration and forged consent", ctx do
    assert {:error, :invalid_request_key} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, %{body: "text"})

    assert {:error, :stale_configuration} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{configuration_version: 9}))

    assert {:error, :invalid_publication_consent} =
             Ideation.create_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea_attrs(%{publication_consent: :facilitator_assisted})
             )

    for visibility <- [:everyone, nil, false] do
      assert {:error, :invalid_visibility} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{visibility: visibility}))
    end

    assert {:error, _} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{title: <<255>>}))

    for id <- [nil, "1", -1, 9_223_372_036_854_775_808] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, id)
      assert {:error, :not_found} = Ideation.reveal_ideas(ctx.author, ctx.project.id, ctx.session.id, id)
      assert {:error, :not_found} = Ideation.list_ideas(ctx.author, ctx.project.id, id)
    end

    idea = idea_fixture(ctx)

    for revision <- [nil, "1", 0, -1, 2_147_483_648] do
      assert {:error, :invalid_edit} =
               Ideation.update_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, revision, edit_attrs(%{}))
    end
  end
end
