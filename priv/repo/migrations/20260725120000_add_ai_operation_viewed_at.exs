defmodule Storyarn.Repo.Migrations.AddAiOperationViewedAt do
  use Ecto.Migration

  # The slice contract requires "Opening/rendering a result records `viewed`,
  # never `accepted`". A fourth `user_disposition` value would have been wrong:
  # that column holds one TERMINAL outcome, and its `IS NULL` guard is what lets
  # `Results.dismiss/2`, `Results.apply/4` and `maybe_abandon/1` act at all — a
  # viewed operation would have been rejected as `:already_decided` and would
  # never have been recorded as abandoned on expiry.
  #
  # A timestamp keeps disposition terminal, records WHEN rather than merely
  # whether, and makes the distinction the contract actually asks for possible:
  # viewed-then-abandoned versus never-opened.
  #
  # It lives on `ai_operations`, not `ai_results`: result rows are deleted on
  # dismiss, on apply, on expiry and by the project soft-delete trigger, so a
  # stamp there would vanish exactly when it becomes interesting.
  def change do
    alter table(:ai_operations) do
      add :viewed_at, :utc_datetime
    end

    # Same precondition the disposition checks already enforce: only a succeeded
    # operation has a result to look at.
    create constraint(:ai_operations, :ai_operations_viewed_requires_success,
             check: "viewed_at IS NULL OR execution_status = 'succeeded'"
           )
  end
end
