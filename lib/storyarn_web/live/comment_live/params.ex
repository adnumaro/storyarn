defmodule StoryarnWeb.CommentLive.Params do
  @moduledoc false

  @max_id 9_223_372_036_854_775_807
  @max_pages 20
  @defaults %{
    "workspace_id" => "",
    "project_id" => "",
    "tool" => "",
    "status" => "all",
    "personal" => "all",
    "unread" => "",
    "following" => "",
    "search" => ""
  }

  def defaults, do: @defaults
  def max_pages, do: @max_pages

  def filters(params) do
    %{
      "workspace_id" => id_filter(params["workspace_id"]),
      "project_id" => id_filter(params["project_id"]),
      "tool" => choice(params["tool"], ~w(flow sheet scene brainstorming), ""),
      "status" => choice(params["status"], ~w(all open resolved), "all"),
      "personal" => choice(params["personal"], ~w(all participated mentioned), "all"),
      "unread" => toggle(params["unread"]),
      "following" => toggle(params["following"]),
      "search" => search(params["search"])
    }
  end

  def options(filters) do
    [
      status: filters["status"],
      search: filters["search"],
      participated: filters["personal"] == "participated",
      mentioned: filters["personal"] == "mentioned",
      unread: filters["unread"] == "1",
      following: filters["following"] == "1"
    ]
    |> maybe_put(:workspace_id, positive(filters["workspace_id"]))
    |> maybe_put(:project_id, positive(filters["project_id"]))
    |> maybe_put(:tool, if(filters["tool"] != "", do: filters["tool"]))
  end

  def positive(value) when is_integer(value) and value > 0 and value <= @max_id, do: value

  def positive(value) when is_binary(value) and byte_size(value) in 1..19 do
    case Integer.parse(value) do
      {id, ""} -> positive(id)
      _ -> nil
    end
  end

  def positive(_), do: nil

  defp id_filter(value), do: if(id = positive(value), do: to_string(id), else: "")
  defp toggle(value), do: if(value in ["1", 1, true, "true"], do: "1", else: "")
  defp choice(value, choices, fallback), do: if(value in choices, do: value, else: fallback)

  defp search(value) when is_binary(value) and byte_size(value) <= 200 do
    if String.valid?(value) and not String.contains?(value, <<0>>), do: String.trim(value), else: ""
  end

  defp search(_), do: ""
  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
end
