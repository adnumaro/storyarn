defimpl FunWithFlags.Actor, for: Storyarn.AI.Governance.Data.UserRecord do
  @moduledoc "Preserves the canonical `user:{id}` feature-flag actor identity."

  def id(%Storyarn.AI.Governance.Data.UserRecord{id: id}), do: "user:#{id}"
end
