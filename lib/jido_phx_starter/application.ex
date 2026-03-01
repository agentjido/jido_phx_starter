defmodule JidoPhxStarter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JidoPhxStarterWeb.Telemetry,
      JidoPhxStarter.Repo,
      {DNSCluster, query: Application.get_env(:jido_phx_starter, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JidoPhxStarter.PubSub},
      JidoPhxStarter.Jido,
      # Start a worker by calling: JidoPhxStarter.Worker.start_link(arg)
      # {JidoPhxStarter.Worker, arg},
      # Start to serve requests, typically the last entry
      JidoPhxStarterWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :jido_phx_starter]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JidoPhxStarter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JidoPhxStarterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
