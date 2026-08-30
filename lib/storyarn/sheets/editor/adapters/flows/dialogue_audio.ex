defmodule Storyarn.Sheets.Editor.Adapters.Flows.DialogueAudio do
  @moduledoc """
  Narrow command adapter from the Sheet audio workspace to the Flow owner.

  This is the only Sheet-side entrypoint allowed to request an audio mutation
  on a Flow node. It deliberately returns the transport-neutral committed
  snapshot and errors exposed by `Storyarn.Flows`, never a Flow Ecto struct.
  """

  alias Storyarn.Flows

  @spec assign(pos_integer(), pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok,
           %{
             node_id: pos_integer(),
             audio_asset_id: pos_integer() | nil,
             node_snapshot: map()
           }}
          | {:error, term()}
  def assign(project_id, speaker_sheet_id, node_id, audio_asset_id) do
    Flows.assign_dialogue_audio(project_id, speaker_sheet_id, node_id, audio_asset_id)
  end
end
