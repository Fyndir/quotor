defmodule QuotorWeb.PageControllerTest do
  use QuotorWeb.ConnCase, async: true

  test "mentions légales", %{conn: conn} do
    html = conn |> get(~p"/mentions-legales") |> html_response(200)
    assert html =~ "Mentions légales"
    assert html =~ "Render Services"
    assert html =~ "L. 122-5, 4°"
  end

  test "conditions d'utilisation et parodie", %{conn: conn} do
    html = conn |> get(~p"/conditions") |> html_response(200)
    assert html =~ "Exception de parodie"
    assert html =~ "Deckmyn"
  end

  test "le pied de page affiche le copyright de l'auteur de Quotor", %{conn: conn} do
    html = conn |> get(~p"/conditions") |> html_response(200)
    assert html =~ "Quotor — concept, design et code © 2026"
    assert html =~ "Antoine Gamain. Tous droits"
    assert html =~ "propriété de leurs auteurs"
  end

  test "les mentions légales décrivent la propriété de l'application", %{conn: conn} do
    html = conn |> get(~p"/mentions-legales") |> html_response(200)
    assert html =~ "Propriété de l'application"
    assert html =~ "titulaire exclusif des"
    assert html =~ "L. 335-2"
  end

  test "health check", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get(~p"/health") |> json_response(200)
  end
end
