defmodule JidoPhxStarter.Demos.CounterAgent do
  @moduledoc """
  A simple counter agent demonstrating core Jido concepts:
  - Agent as immutable data structure
  - Actions with validated params
  - Signals and signal routing
  - Direct strategy (synchronous execution)
  """
  use Jido.Agent,
    name: "counter_agent",
    description: "Simple counter demonstration",
    schema: [
      count: [type: :integer, default: 0]
    ]

  alias JidoPhxStarter.Demos.Counter.{IncrementAction, DecrementAction, ResetAction}

  @impl true
  def signal_routes do
    [
      {"counter.increment", IncrementAction},
      {"counter.decrement", DecrementAction},
      {"counter.reset", ResetAction}
    ]
  end
end
