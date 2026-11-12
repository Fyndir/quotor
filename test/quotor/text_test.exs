defmodule Quotor.TextTest do
  use ExUnit.Case, async: true

  doctest Quotor.Text
  doctest Quotor.Catalog.Source

  alias Quotor.Text

  test "tokens/1 découpe en mots normalisés" do
    assert Text.tokens("C'est l'été, Pépé !") == ~w(c est l ete pepe)
    assert Text.tokens("   ") == []
  end

  test "format_ms/1" do
    assert Text.format_ms(65_000) == "1:05"
    assert Text.format_ms(3_725_000) == "1:02:05"
  end
end
