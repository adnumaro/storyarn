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

    # With associations
    project = insert(:project, owner: insert(:user))
  """
  use ExMachina.Ecto, repo: Storyarn.Repo

  # Add factories here as schemas are created.
  # Example:
  #
  # def user_factory do
  #   %Storyarn.Accounts.User{
  #     email: sequence(:email, &"user#{&1}@example.com"),
  #     display_name: Faker.Person.name(),
  #     hashed_password: Bcrypt.hash_pwd_salt("password123")
  #   }
  # end
  #
  # def project_factory do
  #   %Storyarn.Projects.Project{
  #     name: Faker.Company.name(),
  #     description: Faker.Lorem.paragraph(),
  #     owner: build(:user)
  #   }
  # end
end
