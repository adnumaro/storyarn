defmodule Storyarn.Architecture.ProjectsAssetBlobVerificationBoundaryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.AssetBlobVerification
  alias Storyarn.Projects.Assets.AssetOperations

  @verification_contract [
    ensure_active_asset_blobs: 1,
    ensure_asset_blobs: 1,
    ensure_snapshot_asset_blobs: 2
  ]

  test "asset blob verification has one direct owner behind the Assets facade" do
    assert Code.ensure_loaded?(Assets)
    assert Code.ensure_loaded?(AssetBlobVerification)
    assert Code.ensure_loaded?(AssetOperations)

    facade_imports = beam_imports(Assets)

    for {function, arity} <- @verification_contract do
      assert function_exported?(AssetBlobVerification, function, arity)
      assert {AssetBlobVerification, function, arity} in facade_imports

      refute function_exported?(AssetOperations, function, arity)
      refute {AssetOperations, function, arity} in facade_imports
    end

    refute Enum.any?(beam_imports(AssetBlobVerification), fn {module, _function, _arity} ->
             module == AssetOperations
           end)
  end

  defp beam_imports(module) do
    {:ok, {_module, [{:imports, imports}]}} =
      module
      |> :code.which()
      |> :beam_lib.chunks([:imports])

    imports
  end
end
