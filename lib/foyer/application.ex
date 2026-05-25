defmodule Foyer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FoyerWeb.Telemetry,
      Foyer.Repo,
      {DNSCluster, query: Application.get_env(:foyer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foyer.PubSub},
      # Start a worker by calling: Foyer.Worker.start_link(arg)
      # {Foyer.Worker, arg},
      # Start to serve requests, typically the last entry
      FoyerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Foyer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FoyerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
