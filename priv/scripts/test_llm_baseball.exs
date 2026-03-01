# Test script for AshJido LLM integration with baseball cards prompt
# Run with: mix run priv/scripts/test_llm_baseball.exs

alias JidoPhxStarter.Demos.ListingChatAgent

IO.puts("\n=== AshJido LLM Integration Test ===\n")

# Start the agent server directly (not via supervisor)
{:ok, pid} =
  Jido.AgentServer.start_link(
    agent: ListingChatAgent,
    id: "test-agent-#{System.unique_integer([:positive])}",
    jido: JidoPhxStarter.Jido
  )

IO.puts("Agent server started: #{inspect(pid)}")

# Helper to get agent state
get_agent = fn ->
  {:ok, server_state} = Jido.AgentServer.state(pid)
  server_state.agent
end

# Poll for completion (with timeout)
wait_for_completion = fn wait_fn, count ->
  if count > 240 do
    IO.puts("\n\nTimeout waiting for completion!")
    get_agent.()
  else
    Process.sleep(500)
    agent = get_agent.()
    snap = ListingChatAgent.strategy_snapshot(agent)

    if snap.done? do
      IO.puts("\n")
      agent
    else
      # Show progress
      details = snap.details || %{}
      iteration = details[:iteration] || 0
      status = snap.status
      tool_calls = details[:tool_calls] || []
      active_tools = Enum.filter(tool_calls, & &1.status == :running) |> length()
      IO.write("\r[Iteration #{iteration}] Status: #{status} | Tools: #{active_tools} running          ")
      wait_fn.(wait_fn, count + 1)
    end
  end
end

send_and_wait = fn prompt ->
  IO.puts("\n--- Sending: #{prompt} ---\n")
  :ok = ListingChatAgent.ask(pid, prompt)
  IO.puts("Waiting for completion...")
  agent = wait_for_completion.(wait_for_completion, 0)
  IO.puts("Answer:")
  IO.puts(agent.state.last_answer)
  agent
end

# Test with a more specific prompt including prices
prompt = "Create 10 baseball cards from stars in the 1990's. Use $25 for each card and quantity 1."

_agent = send_and_wait.(prompt)

# Check results
IO.puts("\n--- Verifying listings were created ---")

alias JidoPhxStarter.Demos.ListingsDomain.Listing

ctx = %{
  domain: JidoPhxStarter.Demos.ListingsDomain,
  actor: %{id: "00000000-0000-0000-0000-000000000001", role: :user}
}

case Listing.Jido.Read.run(%{}, ctx) do
  {:ok, listings} when is_list(listings) ->
    IO.puts("Found #{length(listings)} listings:")
    Enum.each(listings, fn listing ->
      IO.puts("  - #{listing.title} @ $#{listing.price} (qty: #{listing.quantity}, status: #{listing.status})")
    end)

  {:ok, %{results: listings}} ->
    IO.puts("Found #{length(listings)} listings:")
    Enum.each(listings, fn listing ->
      IO.puts("  - #{listing.title} @ $#{listing.price} (qty: #{listing.quantity}, status: #{listing.status})")
    end)

  {:error, err} ->
    IO.puts("Error listing: #{inspect(err)}")
end

IO.puts("\n=== Test Complete ===\n")
