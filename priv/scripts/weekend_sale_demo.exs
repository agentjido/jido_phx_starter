# priv/scripts/weekend_sale_demo.exs
#
# Multi-Agent Orchestration Demo: "Prepare My Shop for a Weekend Sale"
#
# Demonstrates Jido's native multi-agent patterns:
# - Orchestrator agent spawning specialist children
# - Parallel execution of specialists
# - Child-to-parent communication via emit_to_parent
# - Fan-in of results into a unified plan
#
# Run with:
#   mix run priv/scripts/weekend_sale_demo.exs
#
# Options:
#   --discount=N    Set discount percentage (default: 20)
#   --execute       Actually execute the plan after approval
#   --no-llm        Disable LLM for announcement generation (use templates)

alias JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent
alias JidoPhxStarter.Demos.ListingsDomain
alias JidoPhxStarter.Demos.ListingsDomain.Listing

defmodule WeekendSaleDemo do
  @moduledoc """
  Interactive demo showing multi-agent coordination for sale preparation.
  """

  @poll_interval_ms 100
  @max_wait_ms 10_000

  def run(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:jido_phx_starter)

    discount = Keyword.get(opts, :discount, 20)
    auto_execute = Keyword.get(opts, :execute, false)
    use_llm = Keyword.get(opts, :use_llm, true)

    print_banner(use_llm)

    seed_listings()

    IO.puts("\n#{IO.ANSI.cyan()}Starting Orchestrator Agent...#{IO.ANSI.reset()}")

    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: OrchestratorAgent,
        id: "orchestrator-#{System.unique_integer([:positive])}",
        jido: JidoPhxStarter.Jido
      )

    IO.puts("#{IO.ANSI.green()}✓ Orchestrator started#{IO.ANSI.reset()}")

    send_prepare_signal(pid, discount, use_llm)

    case wait_for_ready(pid) do
      {:ok, final_state} ->
        print_plan(final_state)

        if auto_execute do
          execute_plan(pid)
        else
          prompt_for_execution(pid)
        end

      {:timeout, state} ->
        IO.puts("\n#{IO.ANSI.red()}⚠ Timeout waiting for specialists#{IO.ANSI.reset()}")
        IO.puts("Status: #{inspect(state.status)}")
        IO.puts("Pending: #{inspect(state.pending_specialists)}")
        IO.puts("Results: #{inspect(Map.keys(state.specialist_results))}")
    end

    IO.puts("\n#{IO.ANSI.faint()}Demo complete.#{IO.ANSI.reset()}\n")
    GenServer.stop(pid, :normal)
  end

  defp print_banner(use_llm) do
    llm_status = if use_llm, do: "#{IO.ANSI.green()}✓ LLM Enabled#{IO.ANSI.reset()}", else: "#{IO.ANSI.yellow()}○ Templates Only#{IO.ANSI.reset()}"

    IO.puts("""

    #{IO.ANSI.bright()}#{IO.ANSI.cyan()}═══════════════════════════════════════════════════════════════
    ▓▓▓   Multi-Agent Marketplace Demo   ▓▓▓
    ═══════════════════════════════════════════════════════════════#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Workflow:#{IO.ANSI.reset()} "Prepare My Shop for a Weekend Sale"
    #{IO.ANSI.yellow()}AI Mode:#{IO.ANSI.reset()} #{llm_status}

    #{IO.ANSI.bright()}Architecture:#{IO.ANSI.reset()}
    ┌─────────────────┐
    │  Orchestrator   │  ← Receives "sale.prepare" signal
    └────────┬────────┘
             │
        ┌────┴────┬────────────┐
        ↓         ↓            ↓
    ┌───────┐ ┌───────┐ ┌───────────┐
    │Listings│ │Recomm.│ │ Support   │  ← Spawn in parallel
    └───┬───┘ └───┬───┘ └─────┬─────┘
        │         │           │
        │         │      #{if use_llm, do: "🤖 LLM", else: "📝 TPL"}
        └────┬────┴───────────┘
             ↓
    ┌─────────────────┐
    │  Orchestrator   │  ← Merge results → Present plan
    └─────────────────┘

    """)
  end

  @default_actor %{id: "00000000-0000-0000-0000-000000000001", role: :user}

  defp seed_listings do
    IO.puts("#{IO.ANSI.cyan()}Seeding demo listings...#{IO.ANSI.reset()}")

    listings = [
      %{title: "Vintage Baseball Card - 1952 Topps", price: "150.00", quantity: 1},
      %{title: "Pokemon Charizard 1st Edition", price: "500.00", quantity: 1},
      %{title: "Magic: The Gathering Black Lotus", price: "1000.00", quantity: 1},
      %{title: "Rare Coin Collection (5 coins)", price: "75.00", quantity: 1},
      %{title: "Comic Book - Action Comics #1 Reprint", price: "25.00", quantity: 3}
    ]

    ash_context = %{domain: ListingsDomain, actor: @default_actor}

    Enum.each(listings, fn params ->
      case Listing.Jido.Create.run(params, ash_context) do
        {:ok, listing} ->
          id = get_id(listing)
          title = get_title(listing)
          IO.puts("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Created: #{title} (#{id})")

        {:error, reason} ->
          IO.puts("  #{IO.ANSI.red()}✗#{IO.ANSI.reset()} Failed: #{inspect(reason)}")
      end
    end)

    IO.puts("")
  end

  defp send_prepare_signal(pid, discount, use_llm) do
    llm_note = if use_llm, do: " (LLM enabled)", else: " (templates only)"
    IO.puts("#{IO.ANSI.cyan()}Sending 'sale.prepare' signal with #{discount}% discount#{llm_note}...#{IO.ANSI.reset()}")

    signal =
      Jido.Signal.new!(
        "sale.prepare",
        %{discount_percent: discount, use_llm: use_llm},
        source: "/demo"
      )

    :ok = Jido.AgentServer.cast(pid, signal)

    IO.puts("#{IO.ANSI.green()}✓ Signal sent#{IO.ANSI.reset()}")
    IO.puts("")
    IO.puts("#{IO.ANSI.yellow()}⏱️  Waiting for specialists...#{IO.ANSI.reset()}")
  end

  defp wait_for_ready(pid, elapsed \\ 0) do
    if elapsed >= @max_wait_ms do
      {:ok, server_state} = Jido.AgentServer.state(pid)
      {:timeout, server_state.agent.state}
    else
      {:ok, server_state} = Jido.AgentServer.state(pid)
      agent_state = server_state.agent.state

      print_progress(agent_state)

      case agent_state.status do
        :ready ->
          {:ok, agent_state}

        :done ->
          {:ok, agent_state}

        _ ->
          Process.sleep(@poll_interval_ms)
          wait_for_ready(pid, elapsed + @poll_interval_ms)
      end
    end
  end

  defp print_progress(state) do
    pending = state.pending_specialists || []
    completed = Map.keys(state.specialist_results || %{})

    if completed != [] do
      completed_str =
        completed
        |> Enum.map(&"#{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{&1}")
        |> Enum.join(" ")

      pending_str =
        pending
        |> Enum.map(&"#{IO.ANSI.yellow()}⏳#{IO.ANSI.reset()} #{&1}")
        |> Enum.join(" ")

      IO.write("\r  Progress: #{completed_str} #{pending_str}     ")
    end
  end

  defp print_plan(state) do
    IO.puts("\n\n#{IO.ANSI.bright()}#{IO.ANSI.green()}═══════════════════════════════════════════════════════════════")
    IO.puts("  ✅ All Specialists Complete - Plan Ready")
    IO.puts("═══════════════════════════════════════════════════════════════#{IO.ANSI.reset()}\n")

    results = state.specialist_results || %{}
    plan = state.plan || %{}

    Enum.each(results, fn {specialist, result} ->
      IO.puts("#{IO.ANSI.bright()}#{IO.ANSI.cyan()}▸ #{specialist |> to_string() |> String.capitalize()}:#{IO.ANSI.reset()}")
      IO.puts("  #{result.summary}")

      if result.questions != [] do
        IO.puts("  #{IO.ANSI.yellow()}Questions:#{IO.ANSI.reset()}")
        Enum.each(result.questions, fn q ->
          IO.puts("    • #{q}")
        end)
      end

      IO.puts("")
    end)

    IO.puts("#{IO.ANSI.bright()}#{IO.ANSI.magenta()}═══════════════════════════════════════════════════════════════")
    IO.puts("  📋 Merged Plan")
    IO.puts("═══════════════════════════════════════════════════════════════#{IO.ANSI.reset()}\n")

    price_updates = Map.get(plan, :price_updates, [])
    publish_actions = Map.get(plan, :publish_actions, [])
    bundle_suggestions = Map.get(plan, :bundle_suggestions, [])
    announcement = Map.get(plan, :announcement)
    faqs = Map.get(plan, :faq, [])

    if price_updates != [] do
      IO.puts("#{IO.ANSI.yellow()}Price Updates (#{length(price_updates)}):#{IO.ANSI.reset()}")
      Enum.each(price_updates, fn action ->
        IO.puts("  • #{action[:listing_id]}: $#{action[:current_price]} → $#{action[:new_price]} (-#{action[:discount_percent]}%)")
      end)
      IO.puts("")
    end

    if publish_actions != [] do
      IO.puts("#{IO.ANSI.yellow()}Publish Actions (#{length(publish_actions)}):#{IO.ANSI.reset()}")
      Enum.each(publish_actions, fn action ->
        IO.puts("  • Publish: #{action[:listing_id]}")
      end)
      IO.puts("")
    end

    if bundle_suggestions != [] do
      IO.puts("#{IO.ANSI.yellow()}Bundle Suggestions (#{length(bundle_suggestions)}):#{IO.ANSI.reset()}")
      Enum.each(bundle_suggestions, fn bundle ->
        IO.puts("  • #{bundle[:suggestion]} (+#{bundle[:discount_boost]}% extra off)")
      end)
      IO.puts("")
    end

    if announcement do
      IO.puts("#{IO.ANSI.yellow()}Announcement:#{IO.ANSI.reset()}")
      IO.puts("  #{IO.ANSI.bright()}#{announcement[:title]}#{IO.ANSI.reset()}")
      IO.puts("  Channels: #{Enum.join(announcement[:channels] || [], ", ")}")
      IO.puts("")
    end

    if faqs != [] do
      IO.puts("#{IO.ANSI.yellow()}FAQ Responses (#{length(faqs)}):#{IO.ANSI.reset()}")
      Enum.take(faqs, 2) |> Enum.each(fn faq ->
        IO.puts("  Q: #{faq[:question]}")
        IO.puts("  A: #{faq[:answer]}")
        IO.puts("")
      end)
      if length(faqs) > 2 do
        IO.puts("  ... and #{length(faqs) - 2} more")
      end
    end
  end

  defp prompt_for_execution(pid) do
    IO.puts("\n#{IO.ANSI.bright()}Would you like to execute this plan? (y/n)#{IO.ANSI.reset()}")

    input =
      IO.gets("> ")
      |> case do
        nil -> "n"
        :eof -> "n"
        s -> String.trim(s) |> String.downcase()
      end

    if input in ["y", "yes"] do
      execute_plan(pid)
    else
      IO.puts("#{IO.ANSI.yellow()}Plan not executed.#{IO.ANSI.reset()}")
    end
  end

  defp execute_plan(pid) do
    IO.puts("\n#{IO.ANSI.cyan()}Executing plan...#{IO.ANSI.reset()}")

    signal = Jido.Signal.new!("sale.execute", %{}, source: "/demo")
    :ok = Jido.AgentServer.cast(pid, signal)

    Process.sleep(500)

    {:ok, server_state} = Jido.AgentServer.state(pid)
    results = server_state.agent.state.execution_results || %{}

    executed = results[:executed] || []
    errors = results[:errors] || []

    IO.puts("\n#{IO.ANSI.green()}✅ Executed #{length(executed)} actions#{IO.ANSI.reset()}")

    if errors != [] do
      IO.puts("#{IO.ANSI.red()}⚠ #{length(errors)} errors:#{IO.ANSI.reset()}")
      Enum.each(errors, fn {type, id, reason} ->
        IO.puts("  • #{type} #{id}: #{inspect(reason)}")
      end)
    end

    IO.puts("\n#{IO.ANSI.cyan()}Final Listings:#{IO.ANSI.reset()}")
    ash_context = %{domain: ListingsDomain, actor: @default_actor}

    case Listing.Jido.Read.run(%{}, ash_context) do
      {:ok, listings} when is_list(listings) ->
        Enum.each(listings, fn listing ->
          id = get_id(listing)
          title = get_title(listing)
          price = get_price(listing)
          status = get_status(listing)
          status_color = if status == :published, do: IO.ANSI.green(), else: IO.ANSI.yellow()
          IO.puts("  #{status_color}#{status}#{IO.ANSI.reset()} | $#{price} | #{title} (#{id})")
        end)

      _ ->
        IO.puts("  (Unable to list)")
    end
  end

  defp get_id(%{id: id}), do: id
  defp get_id(%{"id" => id}), do: id
  defp get_id(listing) when is_struct(listing), do: Map.get(listing, :id)
  defp get_id(_), do: "unknown"

  defp get_title(%{title: title}), do: title
  defp get_title(%{"title" => title}), do: title
  defp get_title(listing) when is_struct(listing), do: Map.get(listing, :title)
  defp get_title(_), do: "Untitled"

  defp get_price(%{price: price}), do: price
  defp get_price(%{"price" => price}), do: price
  defp get_price(listing) when is_struct(listing), do: Map.get(listing, :price)
  defp get_price(_), do: "0.00"

  defp get_status(%{status: status}), do: status
  defp get_status(%{"status" => status}), do: status
  defp get_status(listing) when is_struct(listing), do: Map.get(listing, :status)
  defp get_status(_), do: :unknown
end

opts =
  System.argv()
  |> Enum.reduce([], fn
    "--execute", acc ->
      [{:execute, true} | acc]

    "--no-llm", acc ->
      [{:use_llm, false} | acc]

    arg, acc ->
      case Regex.run(~r/--discount=(\d+)/, arg) do
        [_, discount] -> [{:discount, String.to_integer(discount)} | acc]
        nil -> acc
      end
  end)

WeekendSaleDemo.run(opts)
