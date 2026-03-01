defmodule JidoPhxStarterWeb.Demos.CounterLive do
  @moduledoc """
  Demo 1: Counter Agent

  Demonstrates core Jido concepts:
  - Agent as immutable data structure
  - Actions with validated params
  - Signals and signal routing
  - AgentServer.call/3 for synchronous state updates
  """
  use JidoPhxStarterWeb, :live_view

  alias JidoPhxStarter.Demos.CounterAgent
  alias Jido.Signal

  @impl true
  def mount(_params, _session, socket) do
    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: CounterAgent,
        id: "counter-#{System.unique_integer([:positive])}",
        jido: JidoPhxStarter.Jido
      )

    {:ok,
     socket
     |> assign(:agent_pid, pid)
     |> assign(:count, 0)
     |> assign(:last_action, nil)
     |> assign(:signal_history, [])
     |> assign(:total_signals, 0)}
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_event("increment", %{"by" => by}, socket) do
    amount = String.to_integer(by)
    send_signal(socket, "counter.increment", %{by: amount}, "+#{amount}")
  end

  def handle_event("decrement", %{"by" => by}, socket) do
    amount = String.to_integer(by)
    send_signal(socket, "counter.decrement", %{by: amount}, "-#{amount}")
  end

  def handle_event("reset", _params, socket) do
    send_signal(socket, "counter.reset", %{}, "reset")
  end

  defp send_signal(socket, signal_type, data, action_label) do
    start_time = System.monotonic_time(:microsecond)

    signal = Signal.new!(signal_type, data, source: "/demo/counter")
    {:ok, agent} = Jido.AgentServer.call(socket.assigns.agent_pid, signal)

    latency_us = System.monotonic_time(:microsecond) - start_time

    history_entry = %{
      type: signal_type,
      data: data,
      timestamp: DateTime.utc_now(),
      latency_us: latency_us
    }

    {:noreply,
     socket
     |> assign(:count, agent.state.count)
     |> assign(:last_action, action_label)
     |> assign(:signal_history, Enum.take([history_entry | socket.assigns.signal_history], 10))
     |> assign(:total_signals, socket.assigns.total_signals + 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="space-y-6">
        <.header>
          Demo 1: Counter Agent
          <:subtitle>Core Jido concepts: Actions, Signals, AgentServer</:subtitle>
        </.header>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <%!-- Controls Panel --%>
          <div class="card bg-base-200 shadow-lg">
            <div class="card-body">
              <h2 class="card-title text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Controls
              </h2>
              <div class="flex flex-wrap gap-2 mt-4">
                <button
                  id="btn-inc-1"
                  class="btn btn-primary"
                  phx-click="increment"
                  phx-value-by="1"
                >
                  +1
                </button>
                <button
                  id="btn-inc-5"
                  class="btn btn-primary"
                  phx-click="increment"
                  phx-value-by="5"
                >
                  +5
                </button>
                <button
                  id="btn-dec-1"
                  class="btn btn-secondary"
                  phx-click="decrement"
                  phx-value-by="1"
                >
                  -1
                </button>
                <button id="btn-reset" class="btn btn-accent" phx-click="reset">
                  Reset
                </button>
              </div>
              <div class="mt-4 text-sm text-base-content/60">
                <p>Click buttons to emit signals to the agent.</p>
              </div>
            </div>
          </div>

          <%!-- State Panel --%>
          <div class="card bg-base-200 shadow-lg">
            <div class="card-body text-center">
              <h2 class="card-title text-sm font-semibold uppercase tracking-wide text-base-content/70 justify-center">
                Agent State
              </h2>
              <div class="mt-4">
                <div class="text-7xl font-bold tabular-nums" id="count-display">
                  {@count}
                </div>
                <div class="mt-2 text-sm text-base-content/60">
                  <%= if @last_action do %>
                    Last action: <span class="font-mono badge badge-outline">{@last_action}</span>
                  <% else %>
                    No actions yet
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%!-- Telemetry Panel --%>
          <div class="card bg-base-200 shadow-lg">
            <div class="card-body">
              <h2 class="card-title text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Telemetry
              </h2>
              <div class="mt-4 space-y-3">
                <div class="stat p-0">
                  <div class="stat-title text-xs">Total Signals</div>
                  <div class="stat-value text-lg" id="total-signals">{@total_signals}</div>
                </div>

                <div class="divider my-2"></div>

                <div class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Signal History
                </div>
                <div class="max-h-48 overflow-y-auto space-y-1" id="signal-history">
                  <%= if @signal_history == [] do %>
                    <p class="text-sm text-base-content/50 italic">No signals yet</p>
                  <% else %>
                    <%= for entry <- @signal_history do %>
                      <div class="text-xs bg-base-300 rounded px-2 py-1.5">
                        <div class="flex justify-between items-center">
                          <span class="font-mono text-primary">{short_signal(entry.type)}</span>
                          <span class="text-base-content/60">
                            {format_latency(entry.latency_us)}
                          </span>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Concepts Explained --%>
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <h3 class="card-title text-base">Jido Concepts Demonstrated</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2 text-sm">
              <div>
                <span class="font-semibold text-primary">Agent</span>
                <p class="text-base-content/70">
                  Immutable data structure holding state. Defined with a schema for validation.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">Actions</span>
                <p class="text-base-content/70">
                  Pure functions (run/2) that read state and return updates. Params are validated.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">Signals</span>
                <p class="text-base-content/70">
                  Typed messages that trigger actions via signal_routes mapping.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">AgentServer</span>
                <p class="text-base-content/70">
                  GenServer that runs agents. call/3 is synchronous, blocks until done.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_latency(us) when us < 1000, do: "#{us}µs"
  defp format_latency(us), do: "#{Float.round(us / 1000, 1)}ms"

  defp short_signal("counter." <> action), do: action
  defp short_signal(type), do: type
end
