defmodule Storyarn.AccountsTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Workers.DeliverResetPasswordInstructionsWorker

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = set_password(user_fixture())
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = set_password(user_fixture())

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "prepare_invitation_user/1" do
    test "returns ready users when they already have a password" do
      user = user_fixture()

      assert {:ok, {:ready, ready_user}} = Accounts.prepare_invitation_user(user.email)
      assert ready_user.id == user.id
    end

    test "creates a passwordless user and registration token for a new invitee" do
      email = unique_user_email()

      assert {:ok, {:registration_required, token}} = Accounts.prepare_invitation_user(email)
      assert is_binary(token)

      user = Accounts.get_user_by_email(email)
      assert user
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)

      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end

    test "creates a registration token for an existing passwordless user" do
      user = unconfirmed_user_fixture()

      assert {:ok, {:registration_required, token}} = Accounts.prepare_invitation_user(user.email)
      assert is_binary(token)

      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end

    test "does not complete registration with a stale invite token" do
      email = unique_user_email()

      assert {:ok, {:registration_required, _token}} = Accounts.prepare_invitation_user(email)

      user = Accounts.get_user_by_email(email)
      stale_token_record = Repo.get_by!(UserToken, user_id: user.id, context: "invite")

      assert {:ok, {:registration_required, _new_token}} = Accounts.prepare_invitation_user(email)

      assert {:error, :stale_invite_token} =
               Accounts.complete_registration(user, stale_token_record, %{
                 password: valid_user_password()
               })

      user = Accounts.get_user!(user.id)
      assert is_nil(user.hashed_password)
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "queues token delivery through notification", %{user: user} do
      assert {:ok, :queued} =
               Accounts.deliver_user_reset_password_instructions(user, fn token ->
                 "[TOKEN]#{token}[TOKEN]"
               end)

      assert_enqueued(
        worker: DeliverResetPasswordInstructionsWorker,
        args: %{"email" => user.email}
      )

      token = perform_latest_reset_password_job()
      {:ok, decoded_token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, decoded_token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end

    test "does not disclose missing users" do
      assert {:ok, :queued} =
               Accounts.deliver_user_reset_password_instructions(nil, fn token ->
                 "https://example.com/reset/#{token}"
               end)

      refute Repo.exists?(
               from(job in Oban.Job,
                 where: job.worker == ^inspect(DeliverResetPasswordInstructionsWorker)
               )
             )
    end

    test "replaces previous reset tokens", %{user: user} do
      _first_token = extract_reset_password_token(user)

      second_token = extract_reset_password_token(user)

      {:ok, second_token} = Base.url_decode64(second_token, padding: false)

      assert Repo.aggregate(
               from(token in UserToken,
                 where: token.user_id == ^user.id and token.context == "reset_password"
               ),
               :count
             ) == 1

      assert Repo.get_by(UserToken, token: :crypto.hash(:sha256, second_token))
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token = extract_reset_password_token(user)

      %{user: user, token: token}
    end

    test "returns the user with a valid token", %{user: user, token: token} do
      assert reset_user = Accounts.get_user_by_reset_password_token(token)
      assert reset_user.id == user.id
    end

    test "does not return user with invalid token" do
      refute Accounts.get_user_by_reset_password_token("oops")
    end

    test "does not return user if token expired", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "does not return user if email changed", %{user: user, token: token} do
      {:ok, _user} =
        user
        |> User.email_changeset(%{email: unique_user_email()})
        |> Repo.update()

      refute Accounts.get_user_by_reset_password_token(token)
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      user = user_fixture()

      _token = extract_reset_password_token(user)

      _session_token = Accounts.generate_user_session_token(user)

      %{user: user}
    end

    test "updates the password and deletes all tokens for the user", %{user: user} do
      assert {:ok, {user, expired_tokens}} =
               Accounts.reset_user_password(user, %{
                 password: "new valid password",
                 password_confirmation: "new valid password"
               })

      assert expired_tokens != []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "validates password", %{user: user} do
      assert {:error, changeset} =
               Accounts.reset_user_password(user, %{
                 password: "short",
                 password_confirmation: "different"
               })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.after?(user_token.inserted_at, user.authenticated_at)
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at
      assert token_inserted_at
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "reauthenticate_user_session/3" do
    test "validates only the requested active token without elevating any session" do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      user = %{user_fixture() | authenticated_at: stale_authenticated_at}
      token = Accounts.generate_user_session_token(user)
      other_token = Accounts.generate_user_session_token(user)
      original_token = Repo.get_by!(UserToken, token: token)
      original_other_token = Repo.get_by!(UserToken, token: other_token)

      refute Accounts.sudo_mode?(user)

      assert {:ok, reauthenticated_user} =
               Accounts.reauthenticate_user_session(
                 Scope.for_user(user),
                 token,
                 valid_user_password()
               )

      refute Accounts.sudo_mode?(reauthenticated_user)
      assert reauthenticated_user.authenticated_at == stale_authenticated_at

      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      refute Accounts.sudo_mode?(session_user)
      assert Repo.get_by!(UserToken, token: token) == original_token
      assert Repo.get_by!(UserToken, token: other_token) == original_other_token
    end

    test "rejects invalid credentials without changing the timestamp" do
      stale_authenticated_at = DateTime.add(DateTime.utc_now(:second), -21, :minute)
      user = %{user_fixture() | authenticated_at: stale_authenticated_at}
      token = Accounts.generate_user_session_token(user)

      assert {:error, :invalid_credentials} =
               Accounts.reauthenticate_user_session(Scope.for_user(user), token, "wrong password")

      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.authenticated_at == stale_authenticated_at
    end

    test "rejects a token owned by another user or an unknown token" do
      user = user_fixture()
      other_user = user_fixture()
      token = Accounts.generate_user_session_token(other_user)

      assert {:error, :invalid_session} =
               Accounts.reauthenticate_user_session(
                 Scope.for_user(user),
                 token,
                 valid_user_password()
               )

      assert {:error, :invalid_session} =
               Accounts.reauthenticate_user_session(
                 Scope.for_user(user),
                 "unknown-token",
                 valid_user_password()
               )
    end

    test "does not revive an expired token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      expired_at = DateTime.add(DateTime.utc_now(:second), -15, :day)
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: expired_at])

      assert {:error, :invalid_session} =
               Accounts.reauthenticate_user_session(
                 Scope.for_user(user),
                 token,
                 valid_user_password()
               )
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "change_user_profile/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = Accounts.change_user_profile(%User{})
    end

    test "allows display_name to be set" do
      changeset = Accounts.change_user_profile(%User{}, %{display_name: "Test User"})
      assert changeset.valid?
      assert get_change(changeset, :display_name) == "Test User"
    end

    test "validates display_name length" do
      long_name = String.duplicate("a", 101)
      changeset = Accounts.change_user_profile(%User{}, %{display_name: long_name})
      assert "should be at most 100 character(s)" in errors_on(changeset).display_name
    end

    test "validates avatar_url format" do
      changeset = Accounts.change_user_profile(%User{}, %{avatar_url: "not a url"})
      assert "must be a valid URL" in errors_on(changeset).avatar_url

      changeset =
        Accounts.change_user_profile(%User{}, %{avatar_url: "https://example.com/avatar.png"})

      assert changeset.valid?
    end
  end

  describe "update_user_profile/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates display_name", %{user: user} do
      assert {:ok, updated_user} = Accounts.update_user_profile(user, %{display_name: "New Name"})
      assert updated_user.display_name == "New Name"
    end

    test "updates avatar_url", %{user: user} do
      assert {:ok, updated_user} =
               Accounts.update_user_profile(user, %{avatar_url: "https://example.com/new.png"})

      assert updated_user.avatar_url == "https://example.com/new.png"
    end

    test "returns error with invalid data", %{user: user} do
      assert {:error, changeset} = Accounts.update_user_profile(user, %{avatar_url: "not a url"})
      assert "must be a valid URL" in errors_on(changeset).avatar_url
    end
  end

  defp extract_reset_password_token(user) do
    assert {:ok, :queued} =
             Accounts.deliver_user_reset_password_instructions(user, fn token ->
               "[TOKEN]#{token}[TOKEN]"
             end)

    perform_latest_reset_password_job()
  end

  defp perform_latest_reset_password_job do
    job =
      Repo.one!(
        from(job in Oban.Job,
          where: job.worker == ^inspect(DeliverResetPasswordInstructionsWorker),
          order_by: [desc: job.id],
          limit: 1
        )
      )

    assert :ok = perform_job(DeliverResetPasswordInstructionsWorker, job.args)
    email = receive_delivered_email()

    [_, token | _] = String.split(email.text_body, "[TOKEN]")
    token
  end

  defp receive_delivered_email do
    receive do
      {:email, email} -> email
      {:delivered_email, email} -> email
      {:swoosh, :delivered_email, email} -> email
    after
      500 -> flunk("Expected reset password email to be delivered")
    end
  end
end
