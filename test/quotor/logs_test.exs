defmodule Quotor.LogsTest do
  use ExUnit.Case, async: false

  require Logger

  alias Quotor.Logs

  test "les logs applicatifs sont conservés dans le buffer" do
    # le niveau global de test est :warning
    Logger.error("boom de test #{System.unique_integer()}", source_id: 42)
    Logger.flush()

    [entry | _] = Logs.recent(search: "boom de test")
    assert entry.level == :error
    assert entry.metadata.source_id == "42"
    assert Logs.error_count(5) >= 1
  end

  test "filtrage par niveau" do
    Logger.warning("attention filtrage")
    Logger.flush()

    assert [_ | _] = Logs.recent(level: :warning, search: "attention filtrage")
    assert [] = Logs.recent(level: :error, search: "attention filtrage")
  end
end
