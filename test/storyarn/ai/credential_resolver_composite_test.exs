defmodule Storyarn.AI.CredentialResolver.CompositeTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.CredentialResolver.Composite
  alias Storyarn.AI.ResolvedCredential

  setup do
    original = Application.get_env(:storyarn, Composite)
    Application.put_env(:storyarn, Composite, adapters: %{})

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:storyarn, Composite),
        else: Application.put_env(:storyarn, Composite, original)
    end)
  end

  test "missing lanes fail closed without invoking nil as an adapter" do
    assert {:ok, ref} = CredentialRef.new(:workspace_byok, "missing")
    assert {:error, :credential_unavailable} = Composite.resolve(ref, %{})

    credential = %ResolvedCredential{kind: :workspace_byok, value: "ephemeral-secret"}
    assert :ok = Composite.record_outcome(credential, {:ok, :unused})
  end
end
