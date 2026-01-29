defmodule Storyarn.Factory do
  @moduledoc """
  Test factories using ExMachina.

  Usage:
    # Build (in-memory, not persisted)
    user = build(:user)

    # Insert (persisted to database)
    user = insert(:user)

    # With attribute overrides
    admin = insert(:user, email: "admin@example.com")

  Note: For user fixtures with proper authentication state,
  prefer using Storyarn.AccountsFixtures which handles
  magic link confirmation correctly.
  """
  use ExMachina.Ecto, repo: Storyarn.Repo

  alias Storyarn.Accounts.User

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("Password123!"),
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  def unconfirmed_user_factory do
    %User{
      email: sequence(:email, &"unconfirmed#{&1}@example.com"),
      hashed_password: Bcrypt.hash_pwd_salt("Password123!"),
      confirmed_at: nil
    }
  end
end
