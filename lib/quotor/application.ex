defmodule Quotor.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Quotor.Logs,
      QuotorWeb.Telemetry,
      Quotor.Repo,
      Quotor.RateLimit,
      {Oban, Application.fetch_env!(:quotor, Oban)},
      {DNSCluster, query: Application.get_env(:quotor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Quotor.PubSub},
      # Start to serve requests, typically the last entry
      QuotorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quotor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuotorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
