defmodule Quotor.Ingest.WhisperCppTest do
  use ExUnit.Case, async: true

  alias Quotor.Ingest.WhisperCpp

  # extrait réel de `whisper-cli -ml 1 -sow -ojf` (v1.9.5), raccourci
  @json ~S"""
  {
    "systeminfo": "AVX = 1",
    "model": {"type": "small"},
    "params": {"language": "fr"},
    "result": {"language": "fr"},
    "transcription": [
      {"timestamps": {"from": "00:00:00,290", "to": "00:00:00,390"},
       "offsets": {"from": 290, "to": 390}, "text": "",
       "tokens": [{"text": "[_BEG_]", "offsets": {"from": 0, "to": 0}, "id": 50364, "p": 0.97}]},
      {"timestamps": {"from": "00:00:00,870", "to": "00:00:01,130"},
       "offsets": {"from": 870, "to": 1130}, "text": " sais",
       "tokens": [{"text": " sais", "offsets": {"from": 580, "to": 830}, "id": 11757, "p": 0.9}]},
      {"timestamps": {"from": "00:00:01,800", "to": "00:00:02,600"},
       "offsets": {"from": 1800, "to": 2600}, "text": " complètement",
       "tokens": [
         {"text": " compl", "offsets": {"from": 1800, "to": 2100}, "id": 1, "p": 0.8},
         {"text": "ètement", "offsets": {"from": 2100, "to": 2600}, "id": 2, "p": 0.6}
       ]},
      {"timestamps": {"from": "00:00:00,310", "to": "00:00:00,550"},
       "offsets": {"from": 310, "to": 550}, "text": " Pour",
       "tokens": [{"text": " Pour", "offsets": {"from": 20, "to": 260}, "id": 8732, "p": 0.04}]}
    ]
  }
  """

  test "convertit le JSON de whisper-cli en mots horodatés, dans l'ordre" do
    assert {:ok, words} = WhisperCpp.parse_json(@json)

    assert [
             %{text: "Pour", start_ms: 310, end_ms: 550, prob: p1},
             %{text: "sais", start_ms: 870, end_ms: 1130, prob: p2},
             %{text: "complètement", start_ms: 1800, end_ms: 2600, prob: p3}
           ] = words

    assert_in_delta p1, 0.04, 1.0e-6
    assert_in_delta p2, 0.9, 1.0e-6
    # moyenne des tokens du mot
    assert_in_delta p3, 0.7, 1.0e-6
  end

  test "JSON invalide" do
    assert {:error, _} = WhisperCpp.parse_json("pas du json")
    assert {:error, _} = WhisperCpp.parse_json(~s({"autre": 1}))
  end
end
