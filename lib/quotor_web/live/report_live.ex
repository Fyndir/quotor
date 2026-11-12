defmodule QuotorWeb.ReportLive do
  @moduledoc """
  Formulaire de signalement / demande de retrait, accessible à tous
  (notamment aux ayants droit, sans compte).
  """
  use QuotorWeb, :live_view

  alias Quotor.{Catalog, RateLimit}
  alias Quotor.Catalog.Report

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-xl">
        <h1 class="text-3xl font-black mb-2">Signaler un contenu</h1>
        <p class="text-base-content/70 mb-6">
          Ayant droit, personne filmée ou simple utilisateur : indique-nous le contenu concerné et la
          raison. Les demandes de retrait pour droit d'auteur sont traitées en priorité.
        </p>

        <div :if={@quote} class="mb-6 flex items-center gap-3 rounded-xl bg-base-200 p-3 text-sm">
          <.icon name="hero-film" class="size-5 shrink-0" />
          <span>
            Extrait n° {@quote.id} : « {@quote.text} » — {@quote.source.title}
          </span>
        </div>

        <.form for={@form} id="report-form" phx-change="validate" phx-submit="save">
          <.input
            field={@form[:reason]}
            type="select"
            label="Motif"
            options={Enum.map(Report.reasons(), &{Report.reason_label(&1), &1})}
          />
          <.input
            field={@form[:message]}
            type="textarea"
            label="Description"
            placeholder="Lien du contenu, droits concernés, ce que vous demandez (retrait de l'extrait, de la vidéo entière, de la chaîne…)"
            rows="6"
          />
          <.input
            field={@form[:contact_name]}
            type="text"
            label="Nom (et qualité : auteur, mandataire…)"
          />
          <.input field={@form[:contact_email]} type="email" label="Email de contact" />
          <p class="text-xs text-base-content/60 mb-4">
            En envoyant ce formulaire, vous déclarez de bonne foi que les informations fournies sont
            exactes. Vos coordonnées servent uniquement au traitement de la demande.
          </p>
          <.button class="btn btn-primary w-full" phx-disable-with="Envoi…">
            Envoyer le signalement
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    quote =
      with id when is_binary(id) <- params["quote_id"],
           {int, ""} <- Integer.parse(id) do
        Catalog.get_public_quote(int)
      else
        _ -> nil
      end

    defaults =
      %{"reason" => "copyright"}
      |> then(fn d ->
        case params["montage"] do
          key when is_binary(key) ->
            Map.put(d, "message", "Montage : #{QuotorWeb.Endpoint.url()}/m/#{key}\n")

          _ ->
            d
        end
      end)

    {:ok,
     socket
     |> QuotorWeb.LiveHelpers.assign_rate_key()
     |> assign(
       page_title: "Signaler un contenu",
       quote: quote,
       defaults: defaults,
       form: to_form(Catalog.change_report(defaults), as: "report")
     )}
  end

  @impl true
  def handle_event("validate", %{"report" => params}, socket) do
    changeset =
      params |> with_target(socket) |> Catalog.change_report() |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "report"))}
  end

  def handle_event("save", %{"report" => params}, socket) do
    with :ok <- RateLimit.hit({:report, socket.assigns.rate_key}, 10, :timer.hours(1)),
         {:ok, _report} <- Catalog.create_report(with_target(params, socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "Merci, votre signalement a bien été transmis à l'équipe.")
       |> push_navigate(to: ~p"/")}
    else
      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "Trop de signalements envoyés, réessayez plus tard.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "report"))}
    end
  end

  defp with_target(params, %{assigns: %{quote: nil}}), do: params

  defp with_target(params, %{assigns: %{quote: quote}}),
    do: Map.merge(params, %{"quote_id" => quote.id, "source_id" => quote.source_id})
end
