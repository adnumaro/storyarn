defmodule Storyarn.AI.ExecutionRoute do
  @moduledoc "Resolved, content-free provider route captured on an operation."

  alias Storyarn.AI.CredentialRef

  @enforce_keys [
    :lane,
    :provider,
    :model,
    :credential_ref,
    :payer,
    :assignment_source,
    :consent_basis,
    :policy_version,
    :provider_configuration
  ]
  defstruct [
    :lane,
    :provider,
    :model,
    :credential_ref,
    :payer,
    :assignment_source,
    :consent_basis,
    :policy_version,
    :price_id,
    :price_version,
    :price_units,
    :provider_configuration
  ]

  @type t :: %__MODULE__{}

  def to_map(%__MODULE__{} = route) do
    %{
      "lane" => Atom.to_string(route.lane),
      "provider" => route.provider,
      "model" => route.model,
      "credential_ref" => CredentialRef.to_map(route.credential_ref),
      "payer" => route.payer,
      "assignment_source" => route.assignment_source,
      "consent_basis" => route.consent_basis,
      "policy_version" => route.policy_version,
      "price_id" => route.price_id,
      "price_version" => route.price_version,
      "price_units" => route.price_units,
      "provider_configuration" => route.provider_configuration
    }
  end

  def from_map(%{} = map) do
    with {:ok, lane} <- lane(map["lane"]),
         {:ok, credential_ref} <- CredentialRef.from_map(map["credential_ref"]),
         true <- Enum.all?(["provider", "model", "payer", "assignment_source", "consent_basis"], &is_binary(map[&1])),
         true <- is_integer(map["policy_version"]),
         true <- is_integer(map["price_units"]) and map["price_units"] > 0,
         true <- is_map(map["provider_configuration"]) do
      {:ok,
       %__MODULE__{
         lane: lane,
         provider: map["provider"],
         model: map["model"],
         credential_ref: credential_ref,
         payer: map["payer"],
         assignment_source: map["assignment_source"],
         consent_basis: map["consent_basis"],
         policy_version: map["policy_version"],
         price_id: map["price_id"],
         price_version: map["price_version"],
         price_units: map["price_units"],
         provider_configuration: map["provider_configuration"]
       }}
    else
      _invalid -> {:error, :invalid_execution_route}
    end
  end

  def from_map(_value), do: {:error, :invalid_execution_route}

  defp lane(value) when is_binary(value) do
    case Enum.find([:managed, :personal_byok, :workspace_byok], &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_lane}
      atom -> {:ok, atom}
    end
  end

  defp lane(_value), do: {:error, :invalid_lane}
end
