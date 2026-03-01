defmodule JidoPhxStarterWeb.DemoMetadata do
  @moduledoc """
  Central metadata for Jido demos.

  Keep this as the source of truth when adding/removing demos.
  """

  alias JidoPhxStarterWeb.Demos.{
    ChatLive,
    CounterLive,
    DemandTrackerLive,
    ListingManagerLive,
    WeekendSaleLive
  }

  @demos [
    %{
      id: :counter,
      slug: "counter",
      number: 1,
      title: "Counter Agent",
      description:
        "Core Jido concepts: Agent as immutable data structure, Actions with validated params, Signals and signal routing",
      concepts: ["Agent", "Actions", "Signals", "AgentServer.call/3"],
      live: CounterLive
    },
    %{
      id: :demand_tracker,
      slug: "demand-tracker",
      number: 2,
      title: "Demand Tracker",
      description:
        "Jido Directives: Schedule for delayed/recurring signals, Emit for domain events, State updates vs side effects",
      concepts: ["Directives", "Schedule", "Emit", "State Management"],
      live: DemandTrackerLive
    },
    %{
      id: :chat,
      slug: "chat",
      number: 3,
      title: "AI Chat Agent",
      description:
        "Jido.AI integration: Agent macro, async LLM communication, streaming responses via polling",
      concepts: ["Jido.AI.Agent", "Model Aliases", "Async ask/2", "Strategy Snapshot"],
      live: ChatLive
    },
    %{
      id: :listings,
      slug: "listings",
      number: 4,
      title: "Listing Manager",
      description:
        "AshJido integration: Ash resources as agent tools, AI-driven CRUD operations, policy enforcement",
      concepts: ["AshJido", "Ash Resources", "Generated Actions", "ETS Data Layer"],
      live: ListingManagerLive
    },
    %{
      id: :weekend_sale,
      slug: "weekend-sale",
      number: 5,
      title: "Multi-Agent Weekend Sale",
      description:
        "Multi-agent orchestration: Orchestrator spawning specialists, parallel execution, fan-in results, unified plan execution",
      concepts: ["spawn_agent", "emit_to_parent", "Signal Routing", "Fan-in/Fan-out"],
      live: WeekendSaleLive
    }
  ]

  @spec demos() :: [map()]
  def demos, do: @demos

  @spec canonical_paths() :: [String.t()]
  def canonical_paths, do: Enum.map(@demos, &path/1)

  @spec home_cards() :: [map()]
  def home_cards do
    Enum.map(@demos, fn demo ->
      demo
      |> Map.take([:id, :slug, :number, :title, :description, :concepts])
      |> Map.put(:path, path(demo))
    end)
  end

  @spec path(map()) :: String.t()
  def path(%{slug: slug}), do: "/jido/" <> slug
end
