defmodule Storyarn.Projects.ProjectInvitationTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.ProjectInvitation

  # =============================================================================
  # changeset/2
  # =============================================================================

  describe "changeset/2" do
    test "valid with all required attrs" do
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          email: "user@example.com",
          role: "editor",
          project_id: 1,
          invited_by_id: 1
        })

      assert cs.valid?
    end

    test "invalid without email" do
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          role: "editor",
          project_id: 1,
          invited_by_id: 1
        })

      refute cs.valid?
      assert errors_on(cs)[:email]
    end

    test "uses default role when not provided" do
      # Role defaults to "editor" in schema, so it's valid without explicit role
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          email: "user@example.com",
          project_id: 1,
          invited_by_id: 1
        })

      assert cs.valid?
    end

    test "invalid without project_id" do
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          email: "user@example.com",
          role: "editor",
          invited_by_id: 1
        })

      refute cs.valid?
      assert errors_on(cs)[:project_id]
    end

    test "invalid without invited_by_id" do
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          email: "user@example.com",
          role: "editor",
          project_id: 1
        })

      refute cs.valid?
      assert errors_on(cs)[:invited_by_id]
    end

    test "validates email format" do
      cs =
        ProjectInvitation.changeset(%ProjectInvitation{}, %{
          email: "not-an-email",
          role: "editor",
          project_id: 1,
          invited_by_id: 1
        })

      refute cs.valid?
      assert errors_on(cs)[:email]
    end

    test "validates role inclusion - only editor and viewer" do
      for role <- ~w(editor viewer) do
        cs =
          ProjectInvitation.changeset(%ProjectInvitation{}, %{
            email: "user@example.com",
            role: role,
            project_id: 1,
            invited_by_id: 1
          })

        assert cs.valid?, "Expected role '#{role}' to be valid"
      end
    end

    test "rejects invalid roles" do
      for role <- ~w(admin owner member) do
        cs =
          ProjectInvitation.changeset(%ProjectInvitation{}, %{
            email: "user@example.com",
            role: role,
            project_id: 1,
            invited_by_id: 1
          })

        refute cs.valid?, "Expected role '#{role}' to be invalid"
        assert errors_on(cs)[:role]
      end
    end
  end

  # =============================================================================
  # build_invitation/4
  # =============================================================================

  describe "build_invitation/4" do
    test "returns encoded token and invitation struct" do
      project = %{id: 42}
      invited_by = %{id: 7}

      {encoded_token, invitation} =
        ProjectInvitation.build_invitation(project, invited_by, "User@Example.com")

      assert is_binary(encoded_token)
      assert invitation.project_id == 42
      assert invitation.invited_by_id == 7
      assert invitation.email == "user@example.com"
      assert invitation.role == "editor"
      assert invitation.token != nil
      assert invitation.expires_at != nil
    end

    test "defaults role to editor" do
      {_token, invitation} =
        ProjectInvitation.build_invitation(%{id: 1}, %{id: 1}, "a@b.com")

      assert invitation.role == "editor"
    end

    test "accepts custom role" do
      {_token, invitation} =
        ProjectInvitation.build_invitation(%{id: 1}, %{id: 1}, "a@b.com", "viewer")

      assert invitation.role == "viewer"
    end

    test "lowercases email" do
      {_token, invitation} =
        ProjectInvitation.build_invitation(%{id: 1}, %{id: 1}, "USER@EXAMPLE.COM")

      assert invitation.email == "user@example.com"
    end

    test "sets expiry in the future" do
      {_token, invitation} =
        ProjectInvitation.build_invitation(%{id: 1}, %{id: 1}, "a@b.com")

      assert DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt
    end
  end

  # =============================================================================
  # verify_token_query/1
  # =============================================================================

  describe "verify_token_query/1" do
    test "returns error for invalid token" do
      assert :error = ProjectInvitation.verify_token_query("invalid-token")
    end

    test "returns ok with query for valid-format token" do
      # Build a real invitation to get a real token
      {encoded_token, _invitation} =
        ProjectInvitation.build_invitation(%{id: 1}, %{id: 1}, "a@b.com")

      assert {:ok, query} = ProjectInvitation.verify_token_query(encoded_token)
      assert %Ecto.Query{} = query
    end
  end

  # =============================================================================
  # validity_in_days/0
  # =============================================================================

  describe "validity_in_days/0" do
    test "returns 7" do
      assert ProjectInvitation.validity_in_days() == 7
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
