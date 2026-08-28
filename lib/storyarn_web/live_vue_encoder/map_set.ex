defimpl LiveVue.Encoder, for: MapSet do
  def encode(map_set, _opts), do: MapSet.to_list(map_set)
end
