defmodule JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent do
  @moduledoc """
  Orchestrator agent for multi-agent marketplace coordination.

  Demonstrates Jido's native multi-agent patterns:
  - `Directive.spawn_agent` for spawning child specialists
  - `emit_to_parent` for child-to-parent communication
  - Signal routing for workflow coordination

  Workflow: "Prepare My Shop for a Weekend Sale"
  1. Receives "sale.prepare" signal from user
  2. Spawns 3 specialists in parallel: Listings, Recommendations, Support
  3. Each specialist reports back via "specialist.result" signal
  4. Orchestrator merges results into a unified plan
  5. Optionally executes approved mutations
  """
  use Jido.Agent,
    name: "marketplace_orchestrator",
    description: "Coordinates marketplace operations via specialized sub-agents",
    schema: [
      pending_specialists: [type: {:list, :atom}, default: []],
      specialist_results: [type: :map, default: %{}],
      current_goal: [type: :string, default: nil],
      discount_percent: [type: :integer, default: 20],
      status: [type: :atom, default: :idle],
      plan: [type: :map, default: %{}]
    ]

  alias JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent.Actions.{
    PrepareSaleAction,
    HandleSpecialistResultAction,
    ExecutePlanAction,
    ChildReadyAction
  }

  @impl true
  def signal_routes do
    [
      {"sale.prepare", PrepareSaleAction},
      {"jido.agent.child.started", ChildReadyAction},
      {"specialist.result", HandleSpecialistResultAction},
      {"sale.execute", ExecutePlanAction}
    ]
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent.Actions.PrepareSaleAction do
  @moduledoc """
  Spawns specialist agents for the "Prepare Weekend Sale" workflow.

  Spawns 3 specialists in parallel:
  - ListingsSpecialist: Analyzes listings, calculates discounts
  - RecommendationsSpecialist: Suggests bundles and strategy
  - SupportSpecialist: Drafts customer announcement

  Each specialist is spawned via `Directive.spawn_agent` and will
  report back via `emit_to_parent` when complete.
  """
  use Jido.Action,
    name: "prepare_sale",
    description: "Spawn specialists to prepare a weekend sale",
    schema: [
      discount_percent: [type: :integer, default: 20, doc: "Discount percentage to apply"],
      use_llm: [type: :boolean, default: true, doc: "Whether to use LLM for content generation"]
    ]

  alias Jido.Agent.Directive

  alias JidoPhxStarter.Demos.MultiAgent.Specialists.{
    ListingsSpecialist,
    RecommendationsSpecialist,
    SupportSpecialist
  }

  def run(params, _context) do
    discount = Map.get(params, :discount_percent, 20)
    use_llm = Map.get(params, :use_llm, true)

    directives = [
      Directive.spawn_agent(ListingsSpecialist, :listings,
        meta: %{goal: "analyze_and_discount", discount: discount}
      ),
      Directive.spawn_agent(RecommendationsSpecialist, :recommendations,
        meta: %{goal: "suggest_bundles", discount: discount}
      ),
      Directive.spawn_agent(SupportSpecialist, :support,
        meta: %{goal: "draft_announcement", discount: discount, use_llm: use_llm}
      )
    ]

    {:ok,
     %{
       pending_specialists: [:listings, :recommendations, :support],
       discount_percent: discount,
       current_goal: "Preparing #{discount}% off weekend sale",
       status: :collecting,
       specialist_results: %{}
     }, directives}
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent.Actions.ChildReadyAction do
  @moduledoc """
  Handles the `jido.agent.child.started` signal from spawned specialists.

  When a child agent starts, this action sends a work signal to that child
  to kick off its task based on the metadata passed during spawn.
  """
  use Jido.Action,
    name: "child_ready",
    description: "Send work signal to newly started child agent",
    schema: [
      parent_id: [type: :string, doc: "ID of the parent agent"],
      child_id: [type: :string, doc: "ID of the child agent"],
      child_module: [type: :any, doc: "Module of the child agent"],
      tag: [type: :any, doc: "Tag used when spawning"],
      pid: [type: :any, doc: "PID of the child process"],
      meta: [type: :map, default: %{}, doc: "Metadata passed during spawn"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{tag: tag, pid: pid, meta: meta}, _context) do
    goal = Map.get(meta, :goal, "default")
    discount = Map.get(meta, :discount, 20)
    use_llm = Map.get(meta, :use_llm, true)

    payload =
      %{discount: discount}
      |> maybe_add_llm_flag(goal, use_llm)

    work_signal =
      Signal.new!(
        goal,
        payload,
        source: "/orchestrator"
      )

    directive = Directive.emit_to_pid(work_signal, pid)

    {:ok, %{child_signaled: tag}, [directive]}
  end

  defp maybe_add_llm_flag(payload, "draft_announcement", use_llm) do
    Map.put(payload, :use_llm, use_llm)
  end

  defp maybe_add_llm_flag(payload, _goal, _use_llm), do: payload
end

defmodule JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent.Actions.HandleSpecialistResultAction do
  @moduledoc """
  Handles results from specialist agents and merges them into a plan.

  When all specialists have reported, transitions to :ready status
  with a unified plan ready for execution.
  """
  use Jido.Action,
    name: "handle_specialist_result",
    description: "Process results from a specialist agent",
    schema: [
      specialist: [type: :atom, required: true, doc: "Which specialist reported"],
      summary: [type: :string, required: true, doc: "Summary of specialist work"],
      actions: [type: {:list, :map}, default: [], doc: "Proposed actions"],
      questions: [type: {:list, :string}, default: [], doc: "Questions for user"],
      confidence: [type: :float, default: 1.0, doc: "Confidence score"]
    ]

  def run(
        %{
          specialist: specialist,
          summary: summary,
          actions: actions,
          questions: questions,
          confidence: confidence
        },
        context
      ) do
    current_results = context.state.specialist_results || %{}
    current_pending = context.state.pending_specialists || []

    results =
      Map.put(current_results, specialist, %{
        summary: summary,
        actions: actions,
        questions: questions,
        confidence: confidence
      })

    pending = List.delete(current_pending, specialist)

    if pending == [] do
      plan = merge_plan(results)

      {:ok,
       %{
         specialist_results: results,
         pending_specialists: [],
         status: :ready,
         plan: plan
       }}
    else
      {:ok,
       %{
         specialist_results: results,
         pending_specialists: pending
       }}
    end
  end

  defp merge_plan(results) do
    listings_result = Map.get(results, :listings, %{})
    recommendations_result = Map.get(results, :recommendations, %{})
    support_result = Map.get(results, :support, %{})

    %{
      price_updates:
        Map.get(listings_result, :actions, []) |> Enum.filter(&(&1[:type] == :update_price)),
      publish_actions:
        Map.get(listings_result, :actions, []) |> Enum.filter(&(&1[:type] == :publish)),
      bundle_suggestions: Map.get(recommendations_result, :actions, []),
      strategy_notes: Map.get(recommendations_result, :summary, ""),
      announcement:
        Map.get(support_result, :actions, []) |> Enum.find(&(&1[:type] == :announcement)),
      faq: Map.get(support_result, :actions, []) |> Enum.filter(&(&1[:type] == :faq)),
      all_questions: Enum.flat_map(Map.values(results), fn r -> Map.get(r, :questions, []) end)
    }
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent.Actions.ExecutePlanAction do
  @moduledoc """
  Executes the approved sale plan by applying price updates and publishing.

  Only the orchestrator executes mutations - specialists only propose.
  """
  use Jido.Action,
    name: "execute_plan",
    description: "Execute the approved sale plan",
    schema: []

  alias JidoPhxStarter.Demos.ListingsDomain
  alias JidoPhxStarter.Demos.ListingsDomain.Listing

  @default_actor %{id: "00000000-0000-0000-0000-000000000001", role: :user}

  def run(_params, context) do
    plan = context.state.plan || %{}
    results = %{executed: [], errors: []}
    ash_context = %{domain: ListingsDomain, actor: @default_actor}

    results =
      Enum.reduce(Map.get(plan, :price_updates, []), results, fn action, acc ->
        case Listing.Jido.UpdatePrice.run(
               %{id: action[:listing_id], price: action[:new_price]},
               ash_context
             ) do
          {:ok, _} ->
            %{acc | executed: [{:price_update, action[:listing_id]} | acc.executed]}

          {:error, reason} ->
            %{acc | errors: [{:price_update, action[:listing_id], reason} | acc.errors]}
        end
      end)

    results =
      Enum.reduce(Map.get(plan, :publish_actions, []), results, fn action, acc ->
        case Listing.Jido.Publish.run(%{id: action[:listing_id]}, ash_context) do
          {:ok, _} ->
            %{acc | executed: [{:publish, action[:listing_id]} | acc.executed]}

          {:error, reason} ->
            %{acc | errors: [{:publish, action[:listing_id], reason} | acc.errors]}
        end
      end)

    {:ok,
     %{
       status: :done,
       execution_results: results
     }}
  end
end
