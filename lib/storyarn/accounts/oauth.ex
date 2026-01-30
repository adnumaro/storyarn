defmodule Storyarn.Accounts.OAuth do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.{User, UserIdentity}
  alias Storyarn.Repo

  @doc """
  Finds or creates a user from OAuth provider data.

  If an identity with the provider+provider_id exists, returns the associated user.
  If the email matches an existing user, links the identity to that user.
  Otherwise, creates a new user and identity.
  """
  def find_or_create_user_from_oauth(provider, %Ueberauth.Auth{} = auth, register_user_fn) do
    provider_id = to_string(auth.uid)

    Repo.transact(fn ->
      case get_identity_by_provider(provider, provider_id) do
        %UserIdentity{} = identity ->
          identity = Repo.preload(identity, :user)
          update_identity_from_auth(identity, auth)
          {:ok, identity.user}

        nil ->
          create_user_from_oauth(provider, auth, register_user_fn)
      end
    end)
  end

  @doc """
  Gets an identity by provider and provider_id.
  """
  def get_identity_by_provider(provider, provider_id) do
    Repo.get_by(UserIdentity, provider: to_string(provider), provider_id: to_string(provider_id))
  end

  @doc """
  Gets all identities for a user.
  """
  def list_user_identities(user) do
    UserIdentity
    |> where(user_id: ^user.id)
    |> Repo.all()
  end

  @doc """
  Links an OAuth identity to an existing user.
  """
  def link_oauth_identity(user, provider, %Ueberauth.Auth{} = auth) do
    attrs = identity_attrs_from_auth(provider, auth)

    %UserIdentity{}
    |> UserIdentity.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Unlinks an OAuth identity from a user.

  Will not unlink if it's the user's only authentication method
  (no password and only one identity).
  """
  def unlink_oauth_identity(user, provider) do
    identity = Repo.get_by(UserIdentity, user_id: user.id, provider: to_string(provider))

    identities_count =
      Repo.aggregate(from(i in UserIdentity, where: i.user_id == ^user.id), :count)

    cond do
      is_nil(identity) ->
        {:error, :not_found}

      is_nil(user.hashed_password) and identities_count <= 1 ->
        {:error, :cannot_unlink_only_auth_method}

      true ->
        Repo.delete(identity)
    end
  end

  # Private functions

  defp create_user_from_oauth(provider, auth, register_user_fn) do
    email = get_email_from_auth(auth)

    case Storyarn.Accounts.Users.get_user_by_email(email) do
      %User{} = user ->
        link_identity_to_user(user, provider, auth)

      nil ->
        create_new_user_with_identity(email, provider, auth, register_user_fn)
    end
  end

  defp link_identity_to_user(user, provider, auth) do
    case link_oauth_identity(user, provider, auth) do
      {:ok, _identity} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_new_user_with_identity(email, provider, auth, register_user_fn) do
    with {:ok, user} <- register_user_fn.(%{email: email}),
         {:ok, user} <- confirm_oauth_user(user),
         {:ok, _identity} <- link_oauth_identity(user, provider, auth) do
      {:ok, user}
    end
  end

  defp confirm_oauth_user(user) do
    user
    |> User.confirm_changeset()
    |> Repo.update()
  end

  defp update_identity_from_auth(identity, auth) do
    attrs = %{
      provider_email: get_email_from_auth(auth),
      provider_name: get_name_from_auth(auth),
      provider_avatar: get_avatar_from_auth(auth),
      provider_token: auth.credentials.token,
      provider_refresh_token: auth.credentials.refresh_token
    }

    identity
    |> UserIdentity.changeset(attrs)
    |> Repo.update()
  end

  defp identity_attrs_from_auth(provider, auth) do
    %{
      provider: to_string(provider),
      provider_id: to_string(auth.uid),
      provider_email: get_email_from_auth(auth),
      provider_name: get_name_from_auth(auth),
      provider_avatar: get_avatar_from_auth(auth),
      provider_token: auth.credentials.token,
      provider_refresh_token: auth.credentials.refresh_token,
      provider_meta: %{}
    }
  end

  defp get_email_from_auth(%Ueberauth.Auth{info: info}), do: info.email
  defp get_name_from_auth(%Ueberauth.Auth{info: info}), do: info.name || info.nickname
  defp get_avatar_from_auth(%Ueberauth.Auth{info: info}), do: info.image
end
