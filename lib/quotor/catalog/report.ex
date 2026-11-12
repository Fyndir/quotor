defmodule Quotor.Catalog.Report do
  @moduledoc """
  Signalement d'un contenu, notamment demande de retrait par un ayant droit
  (notification au sens de l'article 16 du règlement (UE) 2022/2065 « DSA »).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @reasons ~w(copyright privacy offensive other)
  @statuses ~w(open resolved rejected)

  schema "reports" do
    field :reason, :string
    field :message, :string
    field :contact_email, :string
    field :contact_name, :string
    field :status, :string, default: "open"
    field :resolution, :string

    belongs_to :quote, Quotor.Catalog.Quote
    belongs_to :source, Quotor.Catalog.Source

    timestamps(type: :utc_datetime)
  end

  def reasons, do: @reasons

  def reason_label("copyright"), do: "Droit d'auteur / ayant droit"
  def reason_label("privacy"), do: "Vie privée / droit à l'image"
  def reason_label("offensive"), do: "Contenu choquant ou illicite"
  def reason_label(_), do: "Autre"

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:reason, :message, :contact_email, :contact_name, :quote_id, :source_id])
    |> validate_required([:reason, :message], message: "obligatoire")
    |> validate_inclusion(:reason, @reasons)
    |> validate_length(:message, min: 10, max: 5000)
    |> validate_length(:contact_name, max: 200)
    |> validate_format(:contact_email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "email invalide")
    |> validate_copyright_contact()
  end

  # Une demande de retrait pour droit d'auteur doit permettre d'identifier et
  # de recontacter le demandeur.
  defp validate_copyright_contact(changeset) do
    if get_field(changeset, :reason) == "copyright" do
      validate_required(changeset, [:contact_email, :contact_name],
        message: "obligatoire pour une demande de retrait"
      )
    else
      changeset
    end
  end

  def resolve_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolution])
    |> validate_inclusion(:status, @statuses)
  end
end
