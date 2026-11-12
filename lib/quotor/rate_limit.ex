defmodule Quotor.RateLimit do
  @moduledoc """
  Limiteur de débit très simple (fenêtre fixe, ETS, mono-nœud), utilisé pour
  les montages (coûteux en CPU) et les signalements.
  """
  use GenServer

  @table :quotor_rate_limit

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Renvoie `:ok` ou `{:error, :rate_limited}`."
  def hit(key, limit, window_ms) do
    window = div(System.system_time(:millisecond), window_ms)
    bucket = {key, window}
    count = :ets.update_counter(@table, bucket, 1, {bucket, 0, window_ms})

    if count > limit, do: {:error, :rate_limited}, else: :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    :timer.send_interval(:timer.minutes(5), :purge)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:purge, state) do
    now = System.system_time(:millisecond)

    :ets.foldl(
      fn {{_key, window} = bucket, _count, window_ms}, _ ->
        if (window + 1) * window_ms < now, do: :ets.delete(@table, bucket)
      end,
      nil,
      @table
    )

    {:noreply, state}
  end
end
