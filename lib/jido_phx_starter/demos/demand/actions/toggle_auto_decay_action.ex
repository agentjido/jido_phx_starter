defmodule JidoPhxStarter.Demos.Demand.ToggleAutoDecayAction do
  @moduledoc """
  Toggles auto-decay on/off.
  When enabled, schedules the first tick via Schedule directive.
  When disabled, clears the token to invalidate any pending scheduled ticks.
  """
  use Jido.Action,
    name: "toggle_auto_decay",
    description: "Toggles auto-decay mode",
    schema: []

  alias Jido.Agent.Directive
  alias Jido.Signal

  @decay_interval_ms 10_000

  @impl true
  def run(_params, context) do
    auto_enabled = Map.get(context.state, :auto_decay_enabled, false)

    if auto_enabled do
      {:ok, %{auto_decay_enabled: false, tick_token: nil}}
    else
      new_token = :erlang.unique_integer([:positive])

      schedule_signal =
        Signal.new!(
          "listing.demand.tick",
          %{auto: true, token: new_token},
          source: "/demo/demand-tracker"
        )

      {:ok, %{auto_decay_enabled: true, tick_token: new_token},
       Directive.schedule(@decay_interval_ms, schedule_signal)}
    end
  end
end
