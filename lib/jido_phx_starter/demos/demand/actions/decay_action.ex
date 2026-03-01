defmodule JidoPhxStarter.Demos.Demand.DecayAction do
  @moduledoc """
  Decays demand toward baseline (50).
  If auto-decay is enabled, schedules the next tick via Schedule directive.
  Uses a token to prevent stale scheduled ticks from executing.
  """
  use Jido.Action,
    name: "decay",
    description: "Decays demand toward baseline",
    schema: [
      auto: [type: :boolean, default: false, doc: "Whether this tick came from auto-decay"],
      token: [type: :any, default: nil, doc: "Token to match for auto ticks"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  @decay_amount 2
  @decay_interval_ms 10_000

  @impl true
  def run(%{auto: auto, token: token}, context) do
    current_token = Map.get(context.state, :tick_token)
    auto_enabled = Map.get(context.state, :auto_decay_enabled, false)

    if auto and token != current_token do
      {:ok, %{}}
    else
      perform_decay(context, auto_enabled)
    end
  end

  defp perform_decay(context, auto_enabled) do
    current_demand = Map.get(context.state, :demand, 50)
    listing_id = Map.get(context.state, :listing_id, "demo-listing")
    ticks = Map.get(context.state, :ticks, 0)
    now = DateTime.utc_now()

    new_demand = decay_toward_zero(current_demand)

    base_state = %{
      demand: new_demand,
      ticks: ticks + 1,
      last_updated_at: now
    }

    directives = build_directives(listing_id, current_demand, new_demand, auto_enabled)
    state_update = maybe_add_token(base_state, auto_enabled)

    {:ok, state_update, directives}
  end

  defp decay_toward_zero(demand) do
    max(demand - @decay_amount, 0)
  end

  defp build_directives(listing_id, old_demand, new_demand, auto_enabled) do
    directives = []

    directives =
      if old_demand != new_demand do
        emit_signal =
          Signal.new!(
            "listing.demand.changed",
            %{
              listing_id: listing_id,
              previous: old_demand,
              current: new_demand,
              delta: new_demand - old_demand,
              reason: :decay
            },
            source: "/demo/demand-tracker"
          )

        [Directive.emit(emit_signal) | directives]
      else
        directives
      end

    if auto_enabled do
      new_token = :erlang.unique_integer([:positive])

      schedule_signal =
        Signal.new!(
          "listing.demand.tick",
          %{auto: true, token: new_token},
          source: "/demo/demand-tracker"
        )

      [Directive.schedule(@decay_interval_ms, schedule_signal) | directives]
    else
      directives
    end
  end

  defp maybe_add_token(state, true) do
    Map.put(state, :tick_token, :erlang.unique_integer([:positive]))
  end

  defp maybe_add_token(state, false), do: state
end
