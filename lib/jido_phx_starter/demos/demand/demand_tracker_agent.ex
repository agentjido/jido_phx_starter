defmodule JidoPhxStarter.Demos.DemandTrackerAgent do
  @moduledoc """
  A demand tracker agent demonstrating Jido Directives:
  - Schedule: Delayed/recurring signals
  - Emit: Domain event publication
  - State updates vs side effects separation
  """
  use Jido.Agent,
    name: "demand_tracker",
    description: "Tracks listing demand with auto-decay",
    schema: [
      listing_id: [type: :string, default: "demo-listing"],
      demand: [type: :integer, default: 50],
      ticks: [type: :integer, default: 0],
      last_updated_at: [type: :any, default: nil],
      auto_decay_enabled: [type: :boolean, default: false],
      tick_token: [type: :any, default: nil]
    ]

  alias JidoPhxStarter.Demos.Demand.{
    BoostAction,
    CoolAction,
    DecayAction,
    ToggleAutoDecayAction
  }

  @impl true
  def signal_routes do
    [
      {"listing.demand.boost", BoostAction},
      {"listing.demand.cool", CoolAction},
      {"listing.demand.tick", DecayAction},
      {"listing.demand.auto_decay.toggle", ToggleAutoDecayAction}
    ]
  end
end
