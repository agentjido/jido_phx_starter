defmodule JidoPhxStarterWeb.HomeLive do
  @moduledoc """
  Home page showing navigation cards to all Jido framework demos.
  """
  use JidoPhxStarterWeb, :live_view

  @demos [
    %{
      path: "/demos/jido/1-counter",
      title: "Counter Agent",
      number: 1,
      description:
        "Core Jido concepts: Agent as immutable data structure, Actions with validated params, Signals and signal routing",
      concepts: ["Agent", "Actions", "Signals", "AgentServer.call/3"]
    },
    %{
      path: "/demos/jido/2-demand-tracker",
      title: "Demand Tracker",
      number: 2,
      description:
        "Jido Directives: Schedule for delayed/recurring signals, Emit for domain events, State updates vs side effects",
      concepts: ["Directives", "Schedule", "Emit", "State Management"]
    },
    %{
      path: "/demos/jido/3-chat",
      title: "AI Chat Agent",
      number: 3,
      description:
        "Jido.AI integration: ReActAgent macro, async LLM communication, streaming responses via polling",
      concepts: ["ReActAgent", "Model Aliases", "Async ask/2", "Strategy Snapshot"]
    },
    %{
      path: "/demos/jido/4-listings",
      title: "Listing Manager",
      number: 4,
      description:
        "AshJido integration: Ash resources as agent tools, AI-driven CRUD operations, policy enforcement",
      concepts: ["AshJido", "Ash Resources", "Generated Actions", "ETS Data Layer"]
    },
    %{
      path: "/demos/jido/5-weekend-sale",
      title: "Multi-Agent Weekend Sale",
      number: 5,
      description:
        "Multi-agent orchestration: Orchestrator spawning specialists, parallel execution, fan-in results, unified plan execution",
      concepts: ["spawn_agent", "emit_to_parent", "Signal Routing", "Fan-in/Fan-out"]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :demos, @demos)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gradient-to-br from-base-200 to-base-300">
        <div class="container mx-auto px-4 py-12">
          <header class="text-center mb-12">
            <h1 class="text-4xl font-bold text-base-content mb-4">
              Jido Agent Framework
            </h1>
            <p class="text-lg text-base-content/70 max-w-2xl mx-auto">
              Interactive demos showcasing the capabilities of the Jido agent framework.
              Each demo builds on concepts from the previous ones.
            </p>
          </header>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-6xl mx-auto">
            <.demo_card :for={demo <- @demos} demo={demo} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp demo_card(assigns) do
    ~H"""
    <a
      href={@demo.path}
      class="group card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 hover:-translate-y-1"
    >
      <div class="card-body">
        <div class="flex items-center gap-3 mb-2">
          <span class="badge badge-primary badge-lg font-mono">{@demo.number}</span>
          <h2 class="card-title text-xl">{@demo.title}</h2>
        </div>

        <p class="text-base-content/70 text-sm leading-relaxed mb-4">
          {@demo.description}
        </p>

        <div class="flex flex-wrap gap-2">
          <span
            :for={concept <- @demo.concepts}
            class="badge badge-outline badge-sm"
          >
            {concept}
          </span>
        </div>

        <div class="card-actions justify-end mt-4">
          <span class="text-primary group-hover:translate-x-1 transition-transform inline-flex items-center gap-1">
            Explore <.icon name="hero-arrow-right" class="w-4 h-4" />
          </span>
        </div>
      </div>
    </a>
    """
  end
end
