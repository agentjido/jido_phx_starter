defmodule JidoPhxStarterWeb.Demos.DemandTrackerLive do
  @moduledoc """
  Demo 2: Listing Demand Tracker

  Demonstrates Jido Directives:
  - Schedule: Delayed/recurring signals for auto-decay
  - Emit: Domain event publication
  - State updates vs side effects separation
  """
  use JidoPhxStarterWeb, :live_view

  alias JidoPhxStarter.Demos.DemandTrackerAgent
  alias Jido.Signal

  @decay_interval_ms 10_000
  @countdown_tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: DemandTrackerAgent,
        id: "demand-tracker-#{System.unique_integer([:positive])}",
        jido: JidoPhxStarter.Jido
      )

    {:ok,
     socket
     |> assign(:agent_pid, pid)
     |> assign(:demand, 50)
     |> assign(:ticks, 0)
     |> assign(:auto_decay_enabled, false)
     |> assign(:last_updated_at, nil)
     |> assign(:last_action, nil)
     |> assign(:signal_history, [])
     |> assign(:directive_history, [])
     |> assign(:total_signals, 0)
     |> assign(:countdown_seconds, 0)
     |> assign(:timer_ref, nil)}
  end

  @impl true
  def terminate(_reason, socket) do
    if ref = socket.assigns[:timer_ref], do: Process.cancel_timer(ref)

    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_info(:countdown_tick, socket) do
    if socket.assigns.auto_decay_enabled do
      new_countdown = socket.assigns.countdown_seconds - 1

      if new_countdown <= 0 do
        socket = do_decay_tick(socket)
        timer_ref = Process.send_after(self(), :countdown_tick, @countdown_tick_ms)

        {:noreply,
         socket
         |> assign(:countdown_seconds, div(@decay_interval_ms, 1000))
         |> assign(:timer_ref, timer_ref)}
      else
        timer_ref = Process.send_after(self(), :countdown_tick, @countdown_tick_ms)

        {:noreply,
         socket
         |> assign(:countdown_seconds, new_countdown)
         |> assign(:timer_ref, timer_ref)}
      end
    else
      {:noreply, assign(socket, :countdown_seconds, 0)}
    end
  end

  defp do_decay_tick(socket) do
    signal =
      Signal.new!("listing.demand.tick", %{auto: false, token: nil},
        source: "/demo/demand-tracker"
      )

    {:ok, agent} = Jido.AgentServer.call(socket.assigns.agent_pid, signal)

    history_entry = %{
      type: "listing.demand.tick",
      data: %{auto: true},
      timestamp: DateTime.utc_now(),
      latency_us: 0
    }

    directive_entry = build_directive_entry("listing.demand.tick", "auto tick")

    socket
    |> assign(:demand, agent.state.demand)
    |> assign(:ticks, agent.state.ticks)
    |> assign(:last_updated_at, agent.state.last_updated_at)
    |> assign(:last_action, "auto tick")
    |> assign(:signal_history, Enum.take([history_entry | socket.assigns.signal_history], 10))
    |> assign(
      :directive_history,
      Enum.take([directive_entry | socket.assigns.directive_history], 10)
    )
    |> assign(:total_signals, socket.assigns.total_signals + 1)
  end

  @impl true
  def handle_event("boost", %{"amount" => amount}, socket) do
    amount = String.to_integer(amount)
    send_signal(socket, "listing.demand.boost", %{amount: amount}, "boost +#{amount}")
  end

  def handle_event("cool", %{"amount" => amount}, socket) do
    amount = String.to_integer(amount)
    send_signal(socket, "listing.demand.cool", %{amount: amount}, "cool -#{amount}")
  end

  def handle_event("tick", _params, socket) do
    send_signal(socket, "listing.demand.tick", %{auto: false, token: nil}, "manual tick")
  end

  def handle_event("toggle_auto_decay", _params, socket) do
    currently_enabled = socket.assigns.auto_decay_enabled
    action_label = if currently_enabled, do: "auto-decay OFF", else: "auto-decay ON"

    socket =
      if currently_enabled do
        if ref = socket.assigns.timer_ref, do: Process.cancel_timer(ref)

        socket
        |> assign(:timer_ref, nil)
        |> assign(:countdown_seconds, 0)
      else
        timer_ref = Process.send_after(self(), :countdown_tick, @countdown_tick_ms)

        socket
        |> assign(:timer_ref, timer_ref)
        |> assign(:countdown_seconds, div(@decay_interval_ms, 1000))
      end

    send_signal(socket, "listing.demand.auto_decay.toggle", %{}, action_label)
  end

  defp send_signal(socket, signal_type, data, action_label) do
    start_time = System.monotonic_time(:microsecond)

    signal = Signal.new!(signal_type, data, source: "/demo/demand-tracker")
    {:ok, agent} = Jido.AgentServer.call(socket.assigns.agent_pid, signal)

    latency_us = System.monotonic_time(:microsecond) - start_time

    history_entry = %{
      type: signal_type,
      data: data,
      timestamp: DateTime.utc_now(),
      latency_us: latency_us
    }

    directive_entry = build_directive_entry(signal_type, action_label)

    {:noreply,
     socket
     |> assign(:demand, agent.state.demand)
     |> assign(:ticks, agent.state.ticks)
     |> assign(:auto_decay_enabled, agent.state.auto_decay_enabled)
     |> assign(:last_updated_at, agent.state.last_updated_at)
     |> assign(:last_action, action_label)
     |> assign(:signal_history, Enum.take([history_entry | socket.assigns.signal_history], 10))
     |> assign(
       :directive_history,
       Enum.take([directive_entry | socket.assigns.directive_history], 10)
     )
     |> assign(:total_signals, socket.assigns.total_signals + 1)}
  end

  defp build_directive_entry(signal_type, action_label) do
    directives =
      case signal_type do
        "listing.demand.boost" -> ["Emit(listing.demand.changed)"]
        "listing.demand.cool" -> ["Emit(listing.demand.changed)"]
        "listing.demand.tick" -> ["Emit(listing.demand.changed)", "Schedule(tick)"]
        "listing.demand.auto_decay.toggle" -> ["Schedule(tick)"]
        _ -> []
      end

    %{
      action: action_label,
      directives: directives,
      timestamp: DateTime.utc_now()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="space-y-6">
        <.header>
          Demo 2: Listing Demand Tracker
          <:subtitle>Jido Directives: Schedule, Emit, and side effects</:subtitle>
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
                  id="btn-boost-10"
                  class="btn btn-success"
                  phx-click="boost"
                  phx-value-amount="10"
                >
                  Boost +10
                </button>
                <button
                  id="btn-boost-25"
                  class="btn btn-success btn-outline"
                  phx-click="boost"
                  phx-value-amount="25"
                >
                  Boost +25
                </button>
                <button
                  id="btn-cool-10"
                  class="btn btn-info"
                  phx-click="cool"
                  phx-value-amount="10"
                >
                  Cool -10
                </button>
                <button
                  id="btn-tick"
                  class="btn btn-warning"
                  phx-click="tick"
                >
                  Manual Tick
                </button>
                <button
                  id="btn-toggle-auto"
                  class={[
                    "btn",
                    if(@auto_decay_enabled, do: "btn-error", else: "btn-primary")
                  ]}
                  phx-click="toggle_auto_decay"
                >
                  <%= if @auto_decay_enabled do %>
                    Stop Auto-Decay
                  <% else %>
                    Start Auto-Decay
                  <% end %>
                </button>
              </div>
              <div class="mt-4 text-sm text-base-content/60">
                <p>Boost/Cool emit domain events. Auto-Decay uses Schedule directive.</p>
              </div>
            </div>
          </div>

          <%!-- State Panel --%>
          <div class="card bg-base-200 shadow-lg">
            <div class="card-body">
              <h2 class="card-title text-sm font-semibold uppercase tracking-wide text-base-content/70 justify-center">
                Agent State
              </h2>
              <div class="mt-4 space-y-4">
                <%!-- Demand Gauge --%>
                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span>Demand</span>
                    <span class="font-mono font-bold">{@demand}/100</span>
                  </div>
                  <div class="w-full bg-base-300 rounded-full h-6 overflow-hidden">
                    <div
                      class={[
                        "h-6 rounded-full transition-all duration-300",
                        demand_color(@demand)
                      ]}
                      style={"width: #{@demand}%"}
                    >
                    </div>
                  </div>
                </div>

                <%!-- Stats --%>
                <div class="grid grid-cols-3 gap-2 text-center">
                  <div class="stat p-2 bg-base-300 rounded min-w-0">
                    <div class="stat-title text-xs truncate">Ticks</div>
                    <div class="stat-value text-xl">{@ticks}</div>
                  </div>
                  <div class="stat p-2 bg-base-300 rounded min-w-0">
                    <div class="stat-title text-xs truncate">Decay</div>
                    <div class={[
                      "stat-value text-base",
                      if(@auto_decay_enabled, do: "text-success", else: "text-base-content/50")
                    ]}>
                      <%= if @auto_decay_enabled do %>
                        <span class="animate-pulse">●</span> ON
                      <% else %>
                        OFF
                      <% end %>
                    </div>
                  </div>
                  <div class="stat p-2 bg-base-300 rounded min-w-0">
                    <div class="stat-title text-xs truncate">Next</div>
                    <div class={[
                      "stat-value text-xl tabular-nums",
                      if(@auto_decay_enabled, do: "text-warning", else: "text-base-content/30")
                    ]}>
                      <%= if @auto_decay_enabled do %>
                        {@countdown_seconds}s
                      <% else %>
                        --
                      <% end %>
                    </div>
                  </div>
                </div>

                <div class="text-center text-sm text-base-content/60">
                  <%= if @last_action do %>
                    Last: <span class="font-mono badge badge-outline">{@last_action}</span>
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
                  <div class="stat-value text-lg">{@total_signals}</div>
                </div>

                <div class="divider my-2"></div>

                <div class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Directive History
                </div>
                <div class="max-h-32 overflow-y-auto space-y-1" id="directive-history">
                  <%= if @directive_history == [] do %>
                    <p class="text-sm text-base-content/50 italic">No directives yet</p>
                  <% else %>
                    <%= for entry <- @directive_history do %>
                      <div class="text-xs bg-base-300 rounded px-2 py-1.5">
                        <div class="flex justify-between items-center">
                          <span class="font-mono text-secondary">{entry.action}</span>
                        </div>
                        <div class="text-base-content/60 mt-0.5">
                          <%= for d <- entry.directives do %>
                            <span class="badge badge-xs badge-outline mr-1">{d}</span>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="divider my-2"></div>

                <div class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Signal History
                </div>
                <div class="max-h-24 overflow-y-auto space-y-1" id="signal-history">
                  <%= if @signal_history == [] do %>
                    <p class="text-sm text-base-content/50 italic">No signals yet</p>
                  <% else %>
                    <%= for entry <- @signal_history do %>
                      <div class="text-xs bg-base-300 rounded px-2 py-1.5">
                        <div class="flex justify-between items-center">
                          <span class="font-mono text-primary">{short_signal(entry.type)}</span>
                          <span class="text-base-content/60">{format_latency(entry.latency_us)}</span>
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
                <span class="font-semibold text-primary">Directives</span>
                <p class="text-base-content/70">
                  Pure descriptions of side effects. Actions return directives; the runtime executes them.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">Schedule</span>
                <p class="text-base-content/70">
                  Delays a signal for later delivery. Used here for recurring auto-decay ticks.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">Emit</span>
                <p class="text-base-content/70">
                  Dispatches domain events via Signal.Dispatch. Decouples agents from consumers.
                </p>
              </div>
              <div>
                <span class="font-semibold text-primary">State vs Effects</span>
                <p class="text-base-content/70">
                  Actions return both state updates AND directives. Clean separation of concerns.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp demand_color(demand) when demand >= 80, do: "bg-error"
  defp demand_color(demand) when demand >= 60, do: "bg-warning"
  defp demand_color(demand) when demand >= 40, do: "bg-success"
  defp demand_color(demand) when demand >= 20, do: "bg-info"
  defp demand_color(_demand), do: "bg-base-content/30"

  defp format_latency(us) when us < 1000, do: "#{us}µs"
  defp format_latency(us), do: "#{Float.round(us / 1000, 1)}ms"

  defp short_signal("listing.demand." <> action), do: action
  defp short_signal(type), do: type
end
