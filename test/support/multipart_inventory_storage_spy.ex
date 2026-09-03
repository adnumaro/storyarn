defmodule Storyarn.MultipartInventoryStorageSpy do
  @moduledoc false

  def incomplete_multipart_upload_summary(prefix, opts) do
    send(self(), {:multipart_summary_requested, prefix, opts})

    case Process.get({__MODULE__, prefix}) do
      {:raise, exception} -> raise exception
      {:exit, reason} -> exit(reason)
      {:throw, reason} -> throw(reason)
      result -> result
    end
  end
end
