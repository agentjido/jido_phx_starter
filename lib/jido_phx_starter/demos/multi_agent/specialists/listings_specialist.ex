defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.ListingsSpecialist do
  @moduledoc """
  Specialist agent for listing analysis and discount calculation.

  Responsibilities:
  - List all marketplace listings
  - Calculate discounted prices
  - Identify unpublished items to publish
  - Report results back to parent orchestrator
  """
  use Jido.Agent,
    name: "listings_specialist",
    description: "Analyzes listings and calculates sale prices",
    schema: [
      discount_applied: [type: :boolean, default: false],
      listings_analyzed: [type: :integer, default: 0]
    ]

  alias JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.AnalyzeListingsAction

  @impl true
  def signal_routes do
    [
      {"analyze_and_discount", AnalyzeListingsAction}
    ]
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.AnalyzeListingsAction do
  @moduledoc """
  Analyzes listings and calculates discount prices for the sale.
  Reports results back to parent via emit_to_parent.
  """
  use Jido.Action,
    name: "analyze_listings",
    description: "Analyze listings and calculate discounts",
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
        actions = build_actions(listings, discount)

        summary =
          "Found #{length(listings)} listings, calculated #{discount}% discount on #{length(actions)} items"

        result_signal =
          Signal.new!(
            "specialist.result",
            %{
              specialist: :listings,
              summary: summary,
              actions: actions,
              questions: [],
              confidence: 0.95
            },
            source: "/listings_specialist"
          )

        directives = build_directives(context.state, result_signal)
        {:ok, %{discount_applied: true, listings_analyzed: length(listings)}, directives}

      {:error, reason} ->
        error_signal =
          Signal.new!(
            "specialist.result",
            %{
              specialist: :listings,
              summary: "Failed to analyze listings: #{inspect(reason)}",
              actions: [],
              questions: [],
              confidence: 0.0
            },
            source: "/listings_specialist"
          )

        directives = build_directives(context.state, error_signal)
        {:ok, %{discount_applied: false}, directives}
    end
  end

  defp build_directives(%{__parent__: %{pid: pid}}, signal) when is_pid(pid) do
    [Directive.emit_to_pid(signal, pid)]
  end

  defp build_directives(_state, _signal) do
    []
  end

  defp build_actions(listings, discount) do
    listings
    |> Enum.flat_map(fn listing ->
      price_action = build_price_action(listing, discount)
      publish_action = build_publish_action(listing)
      [price_action, publish_action] |> Enum.reject(&is_nil/1)
    end)
  end

  defp build_price_action(listing, discount) do
    current_price = get_price(listing)

    if current_price do
      discount_multiplier =
        Decimal.sub(Decimal.new(1), Decimal.div(Decimal.new(discount), Decimal.new(100)))

      new_price = Decimal.mult(current_price, discount_multiplier) |> Decimal.round(2)

      %{
        type: :update_price,
        listing_id: get_id(listing),
        current_price: Decimal.to_string(current_price),
        new_price: Decimal.to_string(new_price),
        discount_percent: discount
      }
    end
  end

  defp build_publish_action(listing) do
    if get_status(listing) == :draft do
      %{
        type: :publish,
        listing_id: get_id(listing)
      }
    end
  end

  defp get_id(%{id: id}), do: id
  defp get_id(%{"id" => id}), do: id
  defp get_id(_), do: nil

  defp get_price(%{price: price}), do: price
  defp get_price(%{"price" => price}), do: price
  defp get_price(_), do: nil

  defp get_status(%{status: status}), do: status
  defp get_status(%{"status" => status}), do: status
  defp get_status(_), do: nil
end
