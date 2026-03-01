defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.SupportSpecialist do
  @moduledoc """
  Specialist agent for customer communication drafting.

  Responsibilities:
  - Draft sale announcement copy using LLM
  - Prepare FAQ responses
  - Generate social media snippets
  - Report results back to parent orchestrator

  This specialist uses Jido.AI for creative announcement generation,
  demonstrating LLM integration within the multi-agent orchestration.
  """
  use Jido.Agent,
    name: "support_specialist",
    description: "Drafts customer-facing sale communications using AI",
    schema: [
      announcement_drafted: [type: :boolean, default: false],
      use_llm: [type: :boolean, default: true]
    ]

  alias JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.DraftAnnouncementAction

  @impl true
  def signal_routes do
    [
      {"draft_announcement", DraftAnnouncementAction}
    ]
  end
end

defmodule JidoPhxStarter.Demos.MultiAgent.Specialists.Actions.DraftAnnouncementAction do
  @moduledoc """
  Drafts sale announcement and FAQ content using LLM.
  Reports results back to parent via emit_to_parent.

  When LLM is enabled:
  - Generates creative, personalized announcement copy
  - Adapts tone based on inventory context
  - Falls back to templates on LLM failure

  When LLM is disabled (or fallback):
  - Uses deterministic templates for fast, reliable output
  """
  use Jido.Action,
    name: "draft_announcement",
    description: "Draft sale announcement and FAQ using AI",
    schema: [
      discount: [type: :integer, default: 20, doc: "Discount percentage"],
      listings: [type: {:list, :map}, default: [], doc: "Current listings for context"],
      use_llm: [type: :boolean, default: true, doc: "Whether to use LLM for generation"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(params, context) do
    discount = Map.get(params, :discount, 20)
    use_llm = Map.get(params, :use_llm, true)
    listings = Map.get(params, :listings, [])

    Logger.debug("SupportSpecialist: discount=#{discount}, use_llm=#{use_llm}")

    {announcement, generation_method} =
      if use_llm do
        case generate_announcement_with_llm(discount, listings) do
          {:ok, llm_announcement} ->
            {llm_announcement, :llm}

          {:error, reason} ->
            Logger.warning("LLM generation failed, using template: #{inspect(reason)}")
            {generate_announcement_template(discount), :template_fallback}
        end
      else
        {generate_announcement_template(discount), :template}
      end

    faqs = generate_faqs(discount)
    actions = [announcement | faqs]

    result_signal =
      Signal.new!(
        "specialist.result",
        %{
          specialist: :support,
          summary:
            "Drafted announcement (#{generation_method}) and #{length(faqs)} FAQ responses",
          actions: actions,
          questions: [],
          confidence: if(generation_method == :llm, do: 0.95, else: 0.90),
          metadata: %{generation_method: generation_method}
        },
        source: "/support_specialist"
      )

    directives = build_directives(context.state, result_signal)
    {:ok, %{announcement_drafted: true}, directives}
  end

  defp build_directives(%{__parent__: %{pid: pid}}, signal) when is_pid(pid) do
    [Directive.emit_to_pid(signal, pid)]
  end

  defp build_directives(_state, _signal) do
    []
  end

  defp generate_announcement_with_llm(discount, listings) do
    listing_context = format_listings_for_prompt(listings)

    prompt = """
    You are a creative marketing copywriter for a collectibles marketplace.

    Write an exciting, engaging sale announcement for a Weekend Sale with #{discount}% off.

    #{listing_context}

    Requirements:
    - Create an attention-grabbing headline with emoji
    - Write compelling body copy (3-4 sentences)
    - Mention the discount prominently
    - Create urgency (weekend only, limited stock)
    - Keep a friendly, enthusiastic tone
    - End with a clear call-to-action

    Respond with ONLY the announcement in this exact format:
    HEADLINE: [your headline here]
    BODY: [your body copy here]
    """

    case Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Complete, %{
           model: "anthropic:claude-haiku-4-5",
           prompt: prompt,
           max_tokens: 300,
           temperature: 0.8
         }) do
      {:ok, %{text: text}} ->
        parse_llm_announcement(text, discount)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_listings_for_prompt([]), do: ""

  defp format_listings_for_prompt(listings) when is_list(listings) do
    items =
      listings
      |> Enum.take(5)
      |> Enum.map(fn listing ->
        title = get_field(listing, :title, "Item")
        price = get_field(listing, :price, "0.00")
        "- #{title} ($#{price})"
      end)
      |> Enum.join("\n")

    """
    Featured items in this sale:
    #{items}

    Use these items to make the announcement more specific and compelling.
    """
  end

  defp get_field(map, key, default) when is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp parse_llm_announcement(text, discount) do
    headline =
      case Regex.run(~r/HEADLINE:\s*(.+?)(?:\n|BODY:)/s, text) do
        [_, h] -> String.trim(h)
        _ -> "🎉 Weekend Sale - #{discount}% Off Everything!"
      end

    body =
      case Regex.run(~r/BODY:\s*(.+)/s, text) do
        [_, b] -> String.trim(b)
        _ -> default_body(discount)
      end

    {:ok,
     %{
       type: :announcement,
       title: headline,
       body: body,
       channels: [:email, :social, :banner],
       generated_by: :llm
     }}
  end

  defp default_body(discount) do
    """
    Don't miss our biggest sale of the season!

    This weekend only, enjoy #{discount}% off on all items in our shop.
    Stock is limited, so shop early for the best selection.

    Sale runs Friday through Sunday. No code needed - prices already reduced!
    """
  end

  defp generate_announcement_template(discount) do
    %{
      type: :announcement,
      title: "🎉 Weekend Sale - #{discount}% Off Everything!",
      body: default_body(discount),
      channels: [:email, :social, :banner],
      generated_by: :template
    }
  end

  defp generate_faqs(discount) do
    [
      %{
        type: :faq,
        question: "When does the sale end?",
        answer: "The #{discount}% off weekend sale ends Sunday at midnight."
      },
      %{
        type: :faq,
        question: "Do I need a coupon code?",
        answer: "No coupon needed! All sale prices are already applied."
      },
      %{
        type: :faq,
        question: "Can I combine this with other offers?",
        answer: "This sale cannot be combined with other discounts or promotions."
      },
      %{
        type: :faq,
        question: "Is shipping included?",
        answer: "Standard shipping rates apply. Orders over $50 get free shipping!"
      }
    ]
  end
end
