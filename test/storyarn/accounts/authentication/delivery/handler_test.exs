defmodule Storyarn.Accounts.Authentication.Delivery.HandlerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts

  test "delivers Account-owned email-change instructions" do
    user = user_fixture()
    url = "https://storyarn.test/users/settings/confirm-email/token"

    assert {:ok, email} =
             Accounts.deliver_user_update_email_instructions(
               user,
               user.email,
               fn _token -> url end
             )

    assert email.to == [{"", user.email}]
    assert email.subject == "Update your email address"
    assert email.text_body =~ "You requested to change your email address"
    assert email.text_body =~ url
    assert email.html_body =~ "Confirm email change"
  end

  test "delivers Account-owned password-reset instructions" do
    email_address = "person@example.com"
    url = "https://storyarn.test/users/reset-password/token"

    assert {:ok, email} =
             Accounts.deliver_reset_password_instructions(email_address, url)

    assert email.to == [{"", email_address}]
    assert email.subject == "Reset your Storyarn password"
    assert email.text_body =~ "This link expires in 24 hours"
    assert email.text_body =~ url
    assert email.html_body =~ "Reset password"
  end
end
