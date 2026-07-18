defmodule Storyarn.Assets.Storage.Local.ConditionalCopyRegistry do
  @moduledoc false

  @registry __MODULE__
  @owner_marker_suffix ".owner"
  @max_owner_marker_size 256

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @spec with_active_copy(String.t(), (-> result)) :: result | {:error, term()}
        when result: term()
  def with_active_copy(path, fun) when is_binary(path) and is_function(fun, 0) do
    case write_owner_marker(path) do
      :ok -> run_registered_copy(path, fun)
      {:error, _reason} = error -> error
    end
  end

  defp run_registered_copy(path, fun) do
    case register(path) do
      :ok ->
        run_copy(path, fun)

      {:error, _reason} = error ->
        remove_owner_marker(path)
        error
    end
  end

  defp run_copy(path, fun) do
    fun.()
  after
    unregister(path)
    remove_owner_marker(path)
  end

  @spec active?(String.t(), integer() | nil) :: boolean()
  def active?(path, stale_cutoff \\ nil) when is_binary(path) do
    case registry_lookup(path) do
      {:ok, [_entry | _rest]} ->
        true

      {:ok, []} ->
        owner_marker_active?(path, stale_cutoff)

      {:error, :registry_unavailable} ->
        true
    end
  end

  @spec remove_inactive_owner_marker(String.t(), integer() | nil) :: :ok | {:error, term()}
  def remove_inactive_owner_marker(path, stale_cutoff \\ nil) when is_binary(path) do
    if active?(path, stale_cutoff), do: :ok, else: remove_owner_marker(path)
  end

  @spec owner_marker_path(String.t()) :: String.t()
  def owner_marker_path(path) when is_binary(path), do: path <> @owner_marker_suffix

  @spec owner_marker?(String.t()) :: boolean()
  def owner_marker?(path) when is_binary(path) do
    path
    |> Path.basename()
    |> String.ends_with?(@owner_marker_suffix)
  end

  @spec copy_path_from_owner_marker(String.t()) :: String.t()
  def copy_path_from_owner_marker(path) when is_binary(path) do
    String.trim_trailing(path, @owner_marker_suffix)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write_owner_marker(path) do
    marker = :erlang.term_to_binary({node(), self()})

    case File.write(owner_marker_path(path), marker, [:binary, :exclusive]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:conditional_copy_owner_marker_failed, reason}}
    end
  end

  # Marker files are private, capped at 256 bytes, and decoded with [:safe].
  # sobelow_skip ["Traversal.FileModule", "Misc.BinToTerm"]
  defp owner_marker_active?(path, stale_cutoff) do
    marker_path = owner_marker_path(path)

    case File.lstat(marker_path, time: :posix) do
      {:ok, %{type: :regular, size: size, mtime: mtime}} when size <= @max_owner_marker_size ->
        case File.read(marker_path) do
          {:ok, marker} ->
            try do
              marker
              |> :erlang.binary_to_term([:safe])
              |> marker_owner_alive?(mtime, stale_cutoff)
            rescue
              _error -> false
            end

          {:error, _reason} ->
            true
        end

      {:ok, %{type: :regular}} ->
        false

      {:ok, _non_regular_stat} ->
        true

      {:error, :enoent} ->
        false

      {:error, _reason} ->
        true
    end
  end

  defp marker_owner_alive?({owner_node, owner}, _mtime, _stale_cutoff) when owner_node == node() and is_pid(owner),
    do: Process.alive?(owner)

  defp marker_owner_alive?({owner_node, owner}, _mtime, nil) when is_atom(owner_node) and is_pid(owner), do: true

  defp marker_owner_alive?({owner_node, owner}, mtime, stale_cutoff)
       when is_atom(owner_node) and is_pid(owner) and is_integer(stale_cutoff), do: mtime > stale_cutoff

  defp marker_owner_alive?(_owner, _mtime, _stale_cutoff), do: false

  defp register(path) do
    case Registry.register(@registry, path, nil) do
      {:ok, _owner} -> :ok
      {:error, {:already_registered, _owner}} -> {:error, :conditional_copy_already_active}
    end
  catch
    :exit, _reason -> {:error, :conditional_copy_registry_unavailable}
  end

  defp unregister(path) do
    Registry.unregister(@registry, path)
  catch
    :exit, _reason -> :ok
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp remove_owner_marker(path) do
    case File.rm(owner_marker_path(path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp registry_lookup(path) do
    {:ok, Registry.lookup(@registry, path)}
  catch
    :exit, _reason -> {:error, :registry_unavailable}
  end
end
