defmodule Storyarn.AI.PersonalRoles do
  @moduledoc """
  Server-owned vocabulary for personal AI preference slots.

  Roles describe how an explicitly initiated task should use the actor's own
  provider account. They never grant workspace access or provider capability.
  """

  alias Storyarn.AI.ModelCatalog.Entry

  @visible_roles [:general_assistant, :writing_assistant, :illustrator, :voice]
  @reserved_roles [:translator]
  @slots @visible_roles

  @spec visible() :: [atom()]
  def visible, do: @visible_roles

  @spec reserved() :: [atom()]
  def reserved, do: @reserved_roles

  @spec slots() :: [atom()]
  def slots, do: @slots

  @spec normalize_slot(atom() | String.t()) :: {:ok, atom()} | {:error, :invalid_preference_slot}
  def normalize_slot(value) when is_atom(value) do
    if value in @slots, do: {:ok, value}, else: {:error, :invalid_preference_slot}
  end

  def normalize_slot(value) when is_binary(value) do
    case Enum.find(@slots, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_preference_slot}
      slot -> {:ok, slot}
    end
  end

  def normalize_slot(_value), do: {:error, :invalid_preference_slot}

  @spec role_for_capability(atom()) :: atom() | nil
  def role_for_capability(:tasks), do: :general_assistant
  def role_for_capability(:suggestions), do: :writing_assistant
  def role_for_capability(:images), do: :illustrator
  def role_for_capability(:speech), do: :voice
  def role_for_capability(:translation), do: :translator
  def role_for_capability(_capability), do: nil

  @spec required_capabilities(atom()) :: [atom()]
  def required_capabilities(:general_assistant), do: [:tasks]
  def required_capabilities(:writing_assistant), do: [:suggestions]
  def required_capabilities(:illustrator), do: [:images]
  def required_capabilities(:voice), do: [:speech]
  def required_capabilities(:translator), do: [:translation]
  def required_capabilities(_slot), do: []

  @spec assignable?(atom(), Entry.t()) :: boolean()
  def assignable?(slot, %Entry{} = entry) when slot in @visible_roles do
    required = required_capabilities(slot)
    required != [] and Enum.all?(required, &(&1 in entry.capabilities))
  end

  def assignable?(_slot, %Entry{}), do: false

  @spec supports_task?(Entry.t(), atom()) :: boolean()
  def supports_task?(%Entry{} = entry, capability), do: capability in entry.capabilities

  @spec public_slots() :: [map()]
  def public_slots do
    Enum.map(@slots, fn slot ->
      %{
        slot: Atom.to_string(slot),
        kind: "role",
        required_capabilities:
          slot
          |> required_capabilities()
          |> Enum.map(&Atom.to_string/1)
      }
    end)
  end
end
