defmodule StoryarnTest.AI.FakeCredentialResolver do
  @moduledoc false
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: :managed, reference: "test-managed"}, _context) do
    {:ok, %ResolvedCredential{kind: :fake, value: :deterministic}}
  end

  def resolve(%CredentialRef{kind: :personal_byok}, _context) do
    {:ok, %ResolvedCredential{kind: :fake, value: :deterministic}}
  end

  def resolve(_ref, _context), do: {:error, :credential_unavailable}

  @impl true
  def record_outcome(_credential, _outcome), do: :ok
end
