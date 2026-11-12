defmodule Quotor.Logs do
  @moduledoc """
  Gestion des logs.

  Les logs « classiques » partent sur la sortie standard (format texte avec
  métadonnées, récupérés par Docker / Render). En parallèle, un handler
  `:logger` (`Quotor.Logs.Handler`) conserve les derniers événements en
  mémoire (ETS, buffer circulaire) pour la page de supervision admin.
  """

  use GenServer

  @table :quotor_logs
  @counter :quotor_logs_seq
  @max_entries 2_000
  @handler_id :quotor_buffer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Derniers logs, du plus récent au plus ancien. Options : `:level`, `:search`, `:limit`."
  def recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    min_level = Keyword.get(opts, :level)
    search = opts |> Keyword.get(:search) |> blank_to_nil()

    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Stream.map(&elem(&1, 1))
      |> Stream.filter(&(is_nil(min_level) or level_gte?(&1.level, min_level)))
      |> Stream.filter(
        &(is_nil(search) or String.contains?(String.downcase(&1.message), String.downcase(search)))
      )
      |> Enum.take(limit)
    end
  end

  @doc "Nombre d'erreurs dans le buffer depuis `minutes` minutes."
  def error_count(minutes \\ 60) do
    since = DateTime.add(DateTime.utc_now(), -minutes, :minute)

    if :ets.whereis(@table) == :undefined do
      0
    else
      :ets.foldl(
        fn {_, e}, acc ->
          if level_gte?(e.level, :error) and DateTime.after?(e.at, since), do: acc + 1, else: acc
        end,
        0,
        @table
      )
    end
  end

  def clear, do: :ets.delete_all_objects(@table)

  @doc false
  def insert(entry) do
    if :ets.whereis(@table) != :undefined do
      seq = :ets.update_counter(@counter, :seq, 1, {:seq, 0})
      :ets.insert(@table, {seq, entry})

      if rem(seq, 200) == 0,
        do: :ets.select_delete(@table, [{{:"$1", :_}, [{:<, :"$1", seq - @max_entries}], [true]}])
    end

    :ok
  end

  @levels %{
    debug: 0,
    info: 1,
    notice: 2,
    warning: 3,
    error: 4,
    critical: 5,
    alert: 6,
    emergency: 7
  }

  def level_gte?(level, min), do: Map.get(@levels, level, 0) >= Map.get(@levels, min, 0)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(s), do: if(String.trim(s) == "", do: nil, else: s)

  ## GenServer : possède les tables ETS et installe le handler

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :ordered_set,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@counter, [:named_table, :public, :set])
    level = Application.get_env(:quotor, :log_buffer_level, :info)
    _ = :logger.remove_handler(@handler_id)
    :ok = :logger.add_handler(@handler_id, Quotor.Logs.Handler, %{level: level})
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    _ = :logger.remove_handler(@handler_id)
    :ok
  end
end
