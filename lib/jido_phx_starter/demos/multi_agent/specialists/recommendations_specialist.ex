defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.RecommendationsSpecialist do
  @moduledoc """
  Specialist agent for bundle and strategy recommendations.

  Responsibilities:
  - Analyze inventory for bundling opportunities
  - Suggest pricing strategies
  - Recommend cross-sell opportunities
  - Report results back to parent orchestrator

  Note: This specialist uses reasoning only (no LLM for MVP),
  applying deterministic rules for bundle suggestions.
  """
  use Jido.Agent,
    name: "recommendations_specialist",
    description: "Provides strategic recommendations for sales",
    schema: [
      strategy_generated: [type: :boolean, default: false]
    ]

  alias JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.GenerateRecommendationsAction

  @impl true
  def signal_routes do
    [
      {"suggest_bundles", GenerateRecommendationsAction}
    ]
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.GenerateRecommendationsAction do
  @moduledoc """
  Generates bundle and strategy recommendations.
  Reports results back to parent via emit_to_parent.
  """
  use Jido.Action,
    name: "generate_recommendations",
    description: "Generate bundle and strategy recommendations",
    schema: [
      discount: [type: :integer, default: 20, doc: "Discount percentage"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal
  alias JidoPhxStarter.Demos.ListingsDomain
  alias JidoPhxStarter.Demos.ListingsDomain.Listing

  @default_actor %{id: "00000000-0000-0000-0000-000000000001", role: :user}

  def run(%{discount: discount}, context) do
    ash_context = %{domain: ListingsDomain, actor: @default_actor}

    case Listing.Jido.Read.run(%{}, ash_context) do
      {:ok, listings} when is_list(listings) ->
        bundles = suggest_bundles(listings)
        strategy = generate_strategy(listings, discount)

        result_signal =
          Signal.new!(
            "specialist.result",
            %{
              specialist: :recommendations,
              summary: strategy,
              actions: bundles,
              questions: generate_questions(listings),
              confidence: 0.80
            },
            source: "/recommendations_specialist"
          )

        directives = build_directives(context.state, result_signal)
        {:ok, %{strategy_generated: true}, directives}

      {:error, reason} ->
        error_signal =
          Signal.new!(
            "specialist.result",
            %{
              specialist: :recommendations,
              summary: "Failed to generate recommendations: #{inspect(reason)}",
              actions: [],
              questions: [],
              confidence: 0.0
            },
            source: "/recommendations_specialist"
          )

        directives = build_directives(context.state, error_signal)
        {:ok, %{strategy_generated: false}, directives}
    end
  end

  defp build_directives(%{__parent__: %{pid: pid}}, signal) when is_pid(pid) do
    [Directive.emit_to_pid(signal, pid)]
  end

  defp build_directives(_state, _signal) do
    []
  end

  defp suggest_bundles(listings) when length(listings) >= 2 do
    listings
    |> Enum.chunk_every(2)
    |> Enum.with_index()
    |> Enum.map(fn {pair, idx} ->
      ids = Enum.map(pair, &get_id/1)
      titles = Enum.map(pair, &get_title/1)

      %{
        type: :bundle,
        bundle_id: "bundle_#{idx + 1}",
        listing_ids: ids,
        suggestion: "Bundle: #{Enum.join(titles, " + ")}",
        discount_boost: 5
      }
    end)
    |> Enum.take(3)
  end

  defp suggest_bundles(_), do: []

  defp generate_strategy(listings, discount) do
    published_count = Enum.count(listings, &(get_status(&1) == :published))
    draft_count = length(listings) - published_count

    "Strategy: Apply #{discount}% discount across #{length(listings)} items. " <>
      "#{published_count} already published, #{draft_count} drafts to publish. " <>
      "Consider bundling related items for additional 5% off."
  end

  defp generate_questions(listings) do
    questions = []

    questions =
      if length(listings) > 5 do
        ["Should I limit the sale to your top 5 items?" | questions]
      else
        questions
      end

    if Enum.any?(listings, &(get_status(&1) == :draft)) do
      ["Should I also publish draft listings?" | questions]
    else
      questions
    end
  end

  defp get_id(%{id: id}), do: id
  defp get_id(%{"id" => id}), do: id
  defp get_id(_), do: nil

  defp get_title(%{title: title}), do: title
  defp get_title(%{"title" => title}), do: title
  defp get_title(_), do: "Untitled"

  defp get_status(%{status: status}), do: status
  defp get_status(%{"status" => status}), do: status
  defp get_status(_), do: nil
end
