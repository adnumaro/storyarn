defmodule StoryarnTest.AI.FakeCredentialResolver do
  @moduledoc false
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: :managed, reference: "test-managed"}) do
    {:ok, %ResolvedCredential{kind: :fake, value: :deterministic}}
  end

  def resolve(_ref), do: {:error, :credential_unavailable}
end
