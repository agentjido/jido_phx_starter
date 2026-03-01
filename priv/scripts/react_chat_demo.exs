# priv/scripts/react_chat_demo.exs
#
# Comprehensive ReAct Agent CLI Demo
#
# Demonstrates the full ReAct loop with rich visibility into:
# - Streaming text and thinking
# - Tool call lifecycle (planned, executing, completed)
# - Conversation history and context
# - Iteration tracking and usage metrics
#
# Run with:
#   mix run priv/scripts/react_chat_demo.exs
#
# Options:
#   --show-thinking      Show model's thinking/reasoning stream
#   --show-conversation  Show full conversation history after each response
#   --verbose            Enable all visibility options

alias JidoPhxStarter.Demos.ChatAgent

defmodule ReactChatDemo do
  @moduledoc """
  Interactive CLI for demonstrating ReAct agent with full observability.
  """

  @poll_interval_ms 80

  defmodule TraceState do
    @moduledoc "Tracks state between polls for delta rendering"
    defstruct text: "",
              thinking: "",
              seen_tool_ids: MapSet.new(),
              completed_tool_ids: MapSet.new(),
              last_iteration: 0,
              iteration_texts: %{}
  end

  def run(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:jido_phx_starter)
    ensure_ai_config!()

    show_thinking = Keyword.get(opts, :show_thinking, false)
    show_conversation = Keyword.get(opts, :show_conversation, false)
    verbose = Keyword.get(opts, :verbose, false)

    opts = %{
      show_thinking: show_thinking || verbose,
      show_conversation: show_conversation || verbose
    }

    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: ChatAgent,
        id: "cli-chat-#{System.unique_integer([:positive])}",
        jido: JidoPhxStarter.Jido
      )

    print_banner()
    loop(pid, opts)
  end

  defp print_banner do
    IO.puts("""

    #{IO.ANSI.bright()}#{IO.ANSI.cyan()}═══════════════════════════════════════════════════════════════
    ▓▓▓   ReAct Agent CLI Demo   ▓▓▓
    ═══════════════════════════════════════════════════════════════#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Model:#{IO.ANSI.reset()} Claude Haiku (fast)
    #{IO.ANSI.yellow()}Tools:#{IO.ANSI.reset()} add, subtract, multiply, divide, square, weather

    #{IO.ANSI.bright()}Example prompts:#{IO.ANSI.reset()}
    • "What is 15 * 23?"
    • "Calculate 100 divided by 4, then square the result"
    • "What's the weather in Chicago?"
    • "Add 5 and 7, then multiply by 3"

    #{IO.ANSI.faint()}Type 'exit' or 'quit' to stop.
    Type '/help' for commands.#{IO.ANSI.reset()}

    """)
  end

  defp loop(pid, opts) do
    input =
      IO.gets("#{IO.ANSI.bright()}#{IO.ANSI.green()}You>#{IO.ANSI.reset()} ")
      |> case do
        nil -> "exit"
        :eof -> "exit"
        s -> String.trim(s)
      end

    cond do
      input in ["exit", "quit"] ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
        IO.puts("\n#{IO.ANSI.cyan()}Goodbye!#{IO.ANSI.reset()}\n")

      input == "" ->
        loop(pid, opts)

      String.starts_with?(input, "/") ->
        opts = handle_command(input, opts)
        loop(pid, opts)

      true ->
        run_query(pid, input, opts)
        loop(pid, opts)
    end
  end

  defp handle_command("/help", opts) do
    IO.puts("""

    #{IO.ANSI.bright()}Commands:#{IO.ANSI.reset()}
      /help              Show this help
      /thinking on|off   Toggle thinking visibility
      /conversation      Show conversation history on|off
      /tools             List available tools
      /status            Show agent status

    """)

    opts
  end

  defp handle_command("/thinking on", opts) do
    IO.puts("#{IO.ANSI.green()}✓ Thinking visibility enabled#{IO.ANSI.reset()}\n")
    %{opts | show_thinking: true}
  end

  defp handle_command("/thinking off", opts) do
    IO.puts("#{IO.ANSI.yellow()}✓ Thinking visibility disabled#{IO.ANSI.reset()}\n")
    %{opts | show_thinking: false}
  end

  defp handle_command("/conversation on", opts) do
    IO.puts("#{IO.ANSI.green()}✓ Conversation history enabled#{IO.ANSI.reset()}\n")
    %{opts | show_conversation: true}
  end

  defp handle_command("/conversation off", opts) do
    IO.puts("#{IO.ANSI.yellow()}✓ Conversation history disabled#{IO.ANSI.reset()}\n")
    %{opts | show_conversation: false}
  end

  defp handle_command("/tools", opts) do
    IO.puts("""

    #{IO.ANSI.bright()}Available Tools:#{IO.ANSI.reset()}
      #{IO.ANSI.cyan()}add#{IO.ANSI.reset()}        - Add two numbers
      #{IO.ANSI.cyan()}subtract#{IO.ANSI.reset()}   - Subtract two numbers
      #{IO.ANSI.cyan()}multiply#{IO.ANSI.reset()}   - Multiply two numbers
      #{IO.ANSI.cyan()}divide#{IO.ANSI.reset()}     - Divide two numbers
      #{IO.ANSI.cyan()}square#{IO.ANSI.reset()}     - Square a number
      #{IO.ANSI.cyan()}weather#{IO.ANSI.reset()}    - Get weather forecast (NWS API)

    """)

    opts
  end

  defp handle_command("/status", opts) do
    IO.puts("""

    #{IO.ANSI.bright()}Current Settings:#{IO.ANSI.reset()}
      show_thinking: #{opts.show_thinking}
      show_conversation: #{opts.show_conversation}

    """)

    opts
  end

  defp handle_command(cmd, opts) do
    IO.puts("#{IO.ANSI.red()}Unknown command: #{cmd}#{IO.ANSI.reset()}")
    IO.puts("Type /help for available commands.\n")
    opts
  end

  defp run_query(pid, input, opts) do
    :ok = ChatAgent.ask(pid, input)

    IO.puts("")
    print_iteration_header(1)

    final_snap = wait_for_answer(pid, %TraceState{}, opts)
    IO.puts("")

    if opts.show_conversation do
      print_conversation_summary(final_snap)
    end

    print_completion_summary(final_snap)
    IO.puts("")
  end

  defp wait_for_answer(pid, trace, opts) do
    {:ok, server_state} = Jido.AgentServer.state(pid)
    agent = server_state.agent
    snap = ChatAgent.strategy_snapshot(agent)

    trace = process_snapshot(snap, trace, opts)

    if snap.done? do
      snap
    else
      Process.sleep(@poll_interval_ms)
      wait_for_answer(pid, trace, opts)
    end
  end

  defp process_snapshot(snap, trace, opts) do
    details = snap.details || %{}

    current_iteration = details[:iteration] || 0
    streaming_text = details[:streaming_text] || ""
    streaming_thinking = details[:streaming_thinking] || ""
    tool_calls = details[:tool_calls] || []

    trace =
      if current_iteration > trace.last_iteration and trace.last_iteration > 0 do
        IO.puts("")
        print_iteration_header(current_iteration)

        iteration_texts =
          Map.put(trace.iteration_texts, trace.last_iteration, trace.text)

        %{trace | last_iteration: current_iteration, text: "", thinking: "", iteration_texts: iteration_texts}
      else
        %{trace | last_iteration: max(current_iteration, trace.last_iteration)}
      end

    if opts.show_thinking do
      trace = render_thinking_delta(streaming_thinking, trace)
      %{trace | thinking: streaming_thinking}
    else
      trace
    end
    |> then(fn trace ->
      trace = render_tool_calls(tool_calls, trace)
      trace = render_text_delta(streaming_text, trace)
      %{trace | text: streaming_text}
    end)
  end

  defp print_iteration_header(iteration) do
    IO.puts("#{IO.ANSI.faint()}─── Iteration #{iteration} ───#{IO.ANSI.reset()}")
    IO.write("#{IO.ANSI.bright()}#{IO.ANSI.blue()}Assistant>#{IO.ANSI.reset()} ")
  end

  defp render_thinking_delta(current_thinking, trace) do
    delta = string_delta(trace.thinking, current_thinking)

    if delta != "" do
      IO.write("#{IO.ANSI.faint()}#{IO.ANSI.italic()}#{delta}#{IO.ANSI.reset()}")
    end

    trace
  end

  defp render_text_delta(current_text, trace) do
    delta = string_delta(trace.text, current_text)

    if delta != "" do
      IO.write(delta)
    end

    trace
  end

  defp render_tool_calls(tool_calls, trace) do
    prev_seen = trace.seen_tool_ids
    prev_completed = trace.completed_tool_ids

    Enum.each(tool_calls, fn tc ->
      unless MapSet.member?(prev_seen, tc.id) do
        IO.puts("")
        IO.puts(
          "  #{IO.ANSI.cyan()}🔧 Tool: #{IO.ANSI.bright()}#{tc.name}#{IO.ANSI.reset()}"
        )

        args_str = format_arguments(tc.arguments)
        IO.puts("  #{IO.ANSI.faint()}Args: #{args_str}#{IO.ANSI.reset()}")
      end
    end)

    Enum.each(tool_calls, fn tc ->
      if tc.status == :completed and not MapSet.member?(prev_completed, tc.id) do
        result_str = format_result(tc.result)
        IO.puts("  #{IO.ANSI.green()}✓ Result: #{result_str}#{IO.ANSI.reset()}")
        IO.write("#{IO.ANSI.bright()}#{IO.ANSI.blue()}Assistant>#{IO.ANSI.reset()} ")
      end
    end)

    seen_ids = MapSet.new(Enum.map(tool_calls, & &1.id))

    completed_ids =
      tool_calls
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    %{trace | seen_tool_ids: seen_ids, completed_tool_ids: completed_ids}
  end

  defp format_arguments(nil), do: "(none)"

  defp format_arguments(args) when is_map(args) do
    args
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(", ")
    |> String.slice(0, 80)
  end

  defp format_arguments(args), do: inspect(args, limit: 5, printable_limit: 80)

  defp format_result(nil), do: "(pending)"
  defp format_result({:ok, result}), do: inspect(result, limit: 5, printable_limit: 100)
  defp format_result({:error, reason}), do: "#{IO.ANSI.red()}Error: #{inspect(reason)}#{IO.ANSI.reset()}"
  defp format_result(result), do: inspect(result, limit: 5, printable_limit: 100)

  defp print_conversation_summary(snap) do
    conversation = get_in(snap.details, [:conversation]) || []

    if conversation != [] do
      IO.puts("\n#{IO.ANSI.bright()}#{IO.ANSI.yellow()}─── Conversation History ───#{IO.ANSI.reset()}")

      Enum.each(conversation, fn msg ->
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"] || ""
        tool_calls = msg[:tool_calls] || msg["tool_calls"]

        case role do
          :system ->
            IO.puts("  #{IO.ANSI.faint()}[SYSTEM] #{String.slice(content, 0, 60)}...#{IO.ANSI.reset()}")

          :user ->
            IO.puts("  #{IO.ANSI.green()}[USER] #{content}#{IO.ANSI.reset()}")

          :assistant ->
            if tool_calls do
              tool_names = Enum.map(tool_calls, & &1[:name]) |> Enum.join(", ")
              IO.puts("  #{IO.ANSI.blue()}[ASSISTANT] Calling tools: #{tool_names}#{IO.ANSI.reset()}")
            else
              IO.puts("  #{IO.ANSI.blue()}[ASSISTANT] #{String.slice(content, 0, 100)}#{IO.ANSI.reset()}")
            end

          :tool ->
            name = msg[:name] || msg["name"]
            IO.puts("  #{IO.ANSI.cyan()}[TOOL:#{name}] #{String.slice(content, 0, 60)}#{IO.ANSI.reset()}")

          _ ->
            IO.puts("  #{IO.ANSI.faint()}[#{role}] #{String.slice(to_string(content), 0, 60)}#{IO.ANSI.reset()}")
        end
      end)
    end
  end

  defp print_completion_summary(snap) do
    details = snap.details || %{}

    IO.puts("\n#{IO.ANSI.faint()}───────────────────────────────────────#{IO.ANSI.reset()}")

    termination = details[:termination_reason] || "unknown"
    iterations = details[:iteration] || 1
    duration_ms = details[:duration_ms]
    usage = details[:usage] || %{}

    status_color =
      case snap.status do
        :success -> IO.ANSI.green()
        :failure -> IO.ANSI.red()
        _ -> IO.ANSI.yellow()
      end

    IO.puts(
      "#{IO.ANSI.faint()}Status:#{IO.ANSI.reset()} #{status_color}#{snap.status}#{IO.ANSI.reset()} " <>
        "(#{termination})"
    )

    IO.puts("#{IO.ANSI.faint()}Iterations:#{IO.ANSI.reset()} #{iterations}")

    if duration_ms do
      IO.puts("#{IO.ANSI.faint()}Duration:#{IO.ANSI.reset()} #{duration_ms}ms")
    end

    if usage != %{} do
      input = usage[:input_tokens] || 0
      output = usage[:output_tokens] || 0
      cache_read = usage[:cache_read_input_tokens] || 0
      cache_create = usage[:cache_creation_input_tokens] || 0

      token_str = "#{input} in / #{output} out"
      cache_str = if cache_read > 0 or cache_create > 0, do: " (cache: #{cache_read}r/#{cache_create}c)", else: ""

      IO.puts("#{IO.ANSI.faint()}Tokens:#{IO.ANSI.reset()} #{token_str}#{cache_str}")
    end
  end

  defp string_delta(prev, curr) do
    prev_len = String.length(prev)
    curr_len = String.length(curr)

    if curr_len > prev_len do
      String.slice(curr, prev_len, curr_len - prev_len)
    else
      ""
    end
  end

  defp ensure_ai_config! do
    key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(key) or key == "" do
      raise """

      ╔══════════════════════════════════════════════════════════════╗
      ║  Missing ANTHROPIC_API_KEY                                   ║
      ╠══════════════════════════════════════════════════════════════╣
      ║  Run with:                                                   ║
      ║    export ANTHROPIC_API_KEY="sk-ant-..."                     ║
      ║    mix run priv/scripts/react_chat_demo.exs                  ║
      ╚══════════════════════════════════════════════════════════════╝
      """
    end
  end
end

opts =
  System.argv()
  |> Enum.reduce([], fn
    "--show-thinking", acc -> [{:show_thinking, true} | acc]
    "--show-conversation", acc -> [{:show_conversation, true} | acc]
    "--verbose", acc -> [{:verbose, true} | acc]
    _, acc -> acc
  end)

ReactChatDemo.run(opts)
