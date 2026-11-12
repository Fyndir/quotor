defmodule Quotor.Logs.Handler do
  @moduledoc "Handler `:logger` qui alimente le buffer mémoire de `Quotor.Logs`."

  @kept_metadata [:request_id, :source_id, :user_id, :module, :function, :line]

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    Quotor.Logs.insert(%{
      at: timestamp(meta),
      level: level,
      message: format(msg, meta),
      metadata: meta |> Map.take(@kept_metadata) |> Map.new(fn {k, v} -> {k, to_s(v)} end)
    })
  rescue
    _ -> :ok
  end

  defp timestamp(%{time: time}) do
    case DateTime.from_unix(time, :microsecond) do
      {:ok, dt} -> DateTime.truncate(dt, :second)
      _ -> DateTime.utc_now(:second)
    end
  end

  defp timestamp(_), do: DateTime.utc_now(:second)

  defp format({:string, chardata}, _meta), do: chardata |> IO.chardata_to_string() |> truncate()

  defp format({:report, report}, meta) do
    case meta do
      %{report_cb: cb} when is_function(cb, 1) ->
        {fmt, args} = cb.(report)
        fmt |> :io_lib.format(args) |> IO.chardata_to_string() |> truncate()

      _ ->
        report |> inspect(limit: 30) |> truncate()
    end
  end

  defp format({fmt, args}, _meta) do
    fmt |> :io_lib.format(args) |> IO.chardata_to_string() |> truncate()
  rescue
    _ -> inspect({fmt, args}) |> truncate()
  end

  defp truncate(s), do: String.slice(s, 0, 2_000)

  defp to_s(v) when is_binary(v), do: v
  defp to_s(v) when is_atom(v) or is_integer(v), do: to_string(v)
  defp to_s(v), do: inspect(v)
end
