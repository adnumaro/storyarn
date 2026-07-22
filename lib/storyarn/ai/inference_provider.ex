defmodule Storyarn.AI.InferenceProvider do
  @moduledoc "Provider-neutral structured-text inference boundary."

  alias Storyarn.AI.ResolvedCredential

  @type request :: %{
          required(:task_id) => String.t(),
          required(:model) => String.t(),
          required(:input) => map() | list(),
          required(:max_output_bytes) => pos_integer(),
          required(:provider_options) => map()
        }

  @type response :: %{
          required(:output) => map() | list(),
          optional(:provider_request_id) => String.t(),
          optional(:input_units) => non_neg_integer(),
          optional(:output_units) => non_neg_integer(),
          optional(:provider_cost) => Decimal.t(),
          optional(:provider_cost_currency) => String.t()
        }

  @type error_reason ::
          :provider_error
          | :invalid_output
          | :rate_limited
          | :unauthorized
          | {:unknown, atom()}

  @callback generate(ResolvedCredential.t(), request()) :: {:ok, response()} | {:error, error_reason()}
end
