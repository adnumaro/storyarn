defmodule Storyarn.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Accounts` context.
  """

  import Ecto.Query

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)
    {:ok, confirmed_user} = Repo.update(User.confirm_changeset(user))
    set_password(confirmed_user)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def set_super_admin(user, value \\ true) do
    user
    |> Ecto.Changeset.change(%{is_super_admin: value})
    |> Repo.update!()
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Creates a mock Ueberauth.Auth struct for OAuth testing.
  """
  def mock_oauth_auth(provider, attrs \\ %{}) do
    uid = attrs[:uid] || "#{provider}_#{System.unique_integer([:positive])}"
    email = attrs[:email] || unique_user_email()
    name = attrs[:name] || "Test User"

    %Ueberauth.Auth{
      uid: uid,
      provider: String.to_atom(provider),
      info: %Ueberauth.Auth.Info{
        email: email,
        name: name,
        nickname: name,
        image: "https://example.com/avatar.png"
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: "mock_access_token_#{System.unique_integer()}",
        refresh_token: "mock_refresh_token_#{System.unique_integer()}",
        expires_at: nil
      },
      extra: %{}
    }
  end

  @doc """
  Creates a user identity fixture linked to an existing user.
  """
  def user_identity_fixture(user, provider \\ "github", attrs \\ %{}) do
    auth = mock_oauth_auth(provider, attrs)
    {:ok, identity} = Accounts.link_oauth_identity(user, provider, auth)
    identity
  end
end
