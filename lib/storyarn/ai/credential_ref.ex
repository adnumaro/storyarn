defmodule Storyarn.AI.CredentialRef do
  @moduledoc "Opaque credential locator. It never contains plaintext secret material."

  @derive {Inspect, except: [:reference]}
  @enforce_keys [:kind, :reference]
  defstruct [:kind, :reference]

  @type t :: %__MODULE__{kind: :managed | :personal_byok | :workspace_byok, reference: String.t()}

  def new(kind, reference)
      when kind in [:managed, :personal_byok, :workspace_byok] and is_binary(reference) and byte_size(reference) > 0 and
             byte_size(reference) <= 200 do
    {:ok, %__MODULE__{kind: kind, reference: reference}}
  end

  def new(_kind, _reference), do: {:error, :invalid_credential_ref}

  def to_map(%__MODULE__{} = ref), do: %{"kind" => Atom.to_string(ref.kind), "reference" => ref.reference}

  def from_map(%{"kind" => kind, "reference" => reference}) when is_binary(kind) do
    case Enum.find([:managed, :personal_byok, :workspace_byok], &(Atom.to_string(&1) == kind)) do
      nil -> {:error, :invalid_credential_ref}
      atom -> new(atom, reference)
    end
  end

  def from_map(_value), do: {:error, :invalid_credential_ref}
end
