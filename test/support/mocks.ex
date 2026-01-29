defmodule Storyarn.Mocks do
  @moduledoc """
  Mox mock definitions for external services.

  Add mocks here as behaviours are created. Example:

      Mox.defmock(Storyarn.HTTPClientMock, for: Storyarn.HTTPClient.Behaviour)
      Mox.defmock(Storyarn.MailerMock, for: Storyarn.Mailer.Behaviour)

  Usage in tests:

      import Mox

      setup :verify_on_exit!

      test "example with mock" do
        expect(Storyarn.HTTPClientMock, :get, fn url ->
          assert url == "https://api.example.com"
          {:ok, %{status: 200, body: "response"}}
        end)

        # ... test code that uses the mock
      end
  """
end
