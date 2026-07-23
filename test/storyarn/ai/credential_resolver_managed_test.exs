defmodule Storyarn.AI.CredentialResolverManagedTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.CredentialResolver.Managed

  setup do
    original = Application.get_env(:storyarn, Managed)

    Application.put_env(:storyarn, Managed,
      credentials: %{
        "storyarn-managed-fireworks-v1" => "fireworks-secret",
        "storyarn-managed-together-v1" => "together-secret"
      }
    )

    on_exit(fn ->
      if original,
        do: Application.put_env(:storyarn, Managed, original),
        else: Application.delete_env(:storyarn, Managed)
    end)
  end

  test "resolves only the credential named by the persisted provider-scoped reference" do
    assert {:ok, fireworks_ref} = CredentialRef.new(:managed, "storyarn-managed-fireworks-v1")
    assert {:ok, together_ref} = CredentialRef.new(:managed, "storyarn-managed-together-v1")

    assert {:ok, fireworks} = Managed.resolve(fireworks_ref)
    assert {:ok, together} = Managed.resolve(together_ref)
    assert fireworks.value == "fireworks-secret"
    assert together.value == "together-secret"
  end

  test "fails closed for an unknown reference" do
    assert {:ok, ref} = CredentialRef.new(:managed, "storyarn-managed-unknown-v1")
    assert {:error, :credential_unavailable} = Managed.resolve(ref)
  end
end
