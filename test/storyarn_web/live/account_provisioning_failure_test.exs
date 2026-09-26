defmodule StoryarnWeb.AccountProvisioningFailureTest do
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.Registration.Commands.Register
  alias Storyarn.Accounts.User
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  setup do
    previous_config = Application.get_env(:storyarn, Register)

    on_exit(fn ->
      case previous_config do
        nil -> Application.delete_env(:storyarn, Register)
        config -> Application.put_env(:storyarn, Register, config)
      end
    end)

    :ok
  end

  test "public registration reports provisioning failure and rolls the account back", %{conn: conn} do
    email = unique_user_email()
    password = valid_user_password()
    before_counts = persistence_counts()
    fail_subscription_provisioning()

    {:ok, view, _html} = live(conn, ~p"/users/register")

    render_click(view, "save", %{
      "user" => %{
        "email" => email,
        "password" => password,
        "password_confirmation" => password
      }
    })

    assert get_flash_vue(view).props["flash"]["error"] ==
             "We couldn't create your workspace. Please try again."

    refute Accounts.get_user_by_email(email)
    assert persistence_counts() == before_counts
  end

  test "workspace invitation reports account preparation failure instead of failing silently", %{
    conn: conn
  } do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    email = unique_user_email()
    {encoded_token, invitation} = workspace_invitation_fixture(workspace, owner, email)
    before_counts = persistence_counts()
    fail_subscription_provisioning()

    {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/#{encoded_token}")

    assert get_flash_vue(view).props["flash"]["error"] ==
             "We couldn't prepare your account. Please try again."

    refute Accounts.get_user_by_email(email)
    assert is_nil(Repo.get!(WorkspaceInvitation, invitation.id).accepted_at)
    assert persistence_counts() == before_counts
  end

  test "project invitation reports account preparation failure instead of failing silently", %{
    conn: conn
  } do
    owner = user_fixture()
    project = project_fixture(owner)
    email = unique_user_email()
    {encoded_token, invitation} = create_invitation_with_token(project, owner, email)
    before_counts = persistence_counts()
    fail_subscription_provisioning()

    {:ok, view, _html} = live(conn, ~p"/projects/invitations/#{encoded_token}")

    assert get_flash_vue(view).props["flash"]["error"] ==
             "We couldn't prepare your account. Please try again."

    refute Accounts.get_user_by_email(email)
    assert is_nil(Repo.get!(ProjectInvitation, invitation.id).accepted_at)
    assert persistence_counts() == before_counts
  end

  defp fail_subscription_provisioning do
    Application.put_env(:storyarn, Register,
      subscription_provisioner: fn _user ->
        {:error, %{code: :subscription_creation_failed, field_errors: %{}}}
      end
    )
  end

  defp persistence_counts do
    %{
      users: Repo.aggregate(User, :count, :id),
      subscriptions: Repo.aggregate(Subscription, :count, :id),
      workspaces: Repo.aggregate(Workspace, :count, :id),
      memberships: Repo.aggregate(WorkspaceMembership, :count, :id)
    }
  end

  defp get_flash_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup")
  end
end
