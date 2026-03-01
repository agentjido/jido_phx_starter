defmodule JidoPhxStarterWeb.Demos.ChatLive do
  @moduledoc """
  Demo: AI Chat Agent with ReAct Loop

  Demonstrates Jido.AI.Agent with full observability:
  - Streaming text display with iteration tracking
  - Tool call lifecycle (planned → executing → completed)
  - Thinking/reasoning visibility
  - Conversation history and usage metrics
  - Toggleable panels for verbose debugging

  Uses polling of strategy_snapshot for real-time updates.
  """
  use JidoPhxStarterWeb, :live_view

  alias JidoPhxStarter.Demos.ChatAgent

  @poll_interval 80

  defmodule Trace do
    @moduledoc "Pure state for tracking snapshot deltas between polls"
    defstruct last_iteration: 0,
              text: "",
              thinking: "",
              seen_tool_ids: MapSet.new(),
              completed_tool_ids: MapSet.new(),
              awaiting_start?: true
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:agent_pid, nil)
      |> assign(:running?, false)
      |> assign(:input, "")
      |> assign(:error, nil)
      |> assign(:trace, %Trace{})
      |> assign(:messages, [])
      |> assign(:panels, %{thinking: "", usage: %{}, conversation: [], config: %{}})
      |> assign(:conversation_history, [])
      |> assign(:visibility, %{thinking: true, usage: true, tools: true, conversation: true})
      |> assign(:poll_ref, nil)

    if connected?(socket) do
      case start_agent() do
        {:ok, pid} ->
          Process.monitor(pid)
          {:ok, assign(socket, :agent_pid, pid)}

        {:error, reason} ->
          {:ok, assign(socket, :error, "Failed to start agent: #{inspect(reason)}")}
      end
    else
      {:ok, socket}
    end
  end

  defp start_agent do
    Jido.AgentServer.start_link(
      agent: ChatAgent,
      id: "chat-#{System.unique_integer([:positive])}",
      jido: JidoPhxStarter.Jido
    )
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_event("update_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("send", _params, socket) do
    input = String.trim(socket.assigns.input)

    if input == "" or socket.assigns.running? or is_nil(socket.assigns.agent_pid) do
      {:noreply, socket}
    else
      :ok = ChatAgent.ask(socket.assigns.agent_pid, input)

      user_msg = %{id: gen_id(), role: :user, content: input}
      pending_msg = %{id: gen_id(), role: :assistant, content: "", pending: true}

      {:noreply,
       socket
       |> assign(:input, "")
       |> assign(:running?, true)
       |> assign(:trace, %Trace{})
       |> assign(:messages, socket.assigns.messages ++ [user_msg, pending_msg])
       |> assign(:panels, %{thinking: "", usage: %{}, conversation: [], config: %{}})
       |> schedule_poll()}
    end
  end

  def handle_event("toggle", %{"key" => key}, socket) do
    case key do
      "thinking" -> {:noreply, toggle_panel(socket, :thinking)}
      "usage" -> {:noreply, toggle_panel(socket, :usage)}
      "tools" -> {:noreply, toggle_panel(socket, :tools)}
      "conversation" -> {:noreply, toggle_panel(socket, :conversation)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("restart_agent", _params, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    case start_agent() do
      {:ok, pid} ->
        Process.monitor(pid)

        {:noreply,
         socket
         |> assign(:agent_pid, pid)
         |> assign(:error, nil)
         |> assign(:running?, false)
         |> assign(:messages, [])
         |> assign(:conversation_history, [])
         |> assign(:trace, %Trace{})}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to restart: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:poll, ref}, %{assigns: %{poll_ref: ref}} = socket) do
    socket = assign(socket, :poll_ref, nil)

    if socket.assigns.running? and socket.assigns.agent_pid do
      case get_snapshot(socket.assigns.agent_pid) do
        {:ok, snap} ->
          {trace, messages, panels} =
            process_snapshot(socket.assigns.trace, socket.assigns.messages, snap)

          conversation = (snap.details || %{})[:conversation] || []

          socket =
            socket
            |> assign(:trace, trace)
            |> assign(:messages, messages)
            |> assign(:panels, panels)
            |> assign(:conversation_history, conversation)

          # Only stop polling if done AND we're not still awaiting the agent to start
          if snap.done? and not trace.awaiting_start? do
            {:noreply, assign(socket, :running?, false)}
          else
            {:noreply, schedule_poll(socket)}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:running?, false)
           |> assign(:error, "Snapshot error: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll, _old_ref}, socket) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, socket) do
    if pid == socket.assigns.agent_pid do
      {:noreply,
       socket
       |> assign(:agent_pid, nil)
       |> assign(:running?, false)
       |> assign(:poll_ref, nil)
       |> assign(:error, "Agent crashed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  defp toggle_panel(socket, panel) do
    visibility = Map.update!(socket.assigns.visibility, panel, &(!&1))
    assign(socket, :visibility, visibility)
  end

  defp schedule_poll(socket) do
    ref = make_ref()
    Process.send_after(self(), {:poll, ref}, @poll_interval)
    assign(socket, :poll_ref, ref)
  end

  defp get_snapshot(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, server_state} ->
        {:ok, ChatAgent.strategy_snapshot(server_state.agent)}

      error ->
        error
    end
  end

  defp process_snapshot(trace, messages, snap) do
    details = snap.details || %{}

    current_iteration = details[:iteration] || 0
    streaming_text = details[:streaming_text] || ""
    streaming_thinking = details[:streaming_thinking] || ""
    tool_calls = details[:tool_calls] || []

    # Check if agent has started processing (moved from idle/completed to running)
    trace =
      if trace.awaiting_start? and snap.status == :running do
        %{trace | awaiting_start?: false}
      else
        trace
      end

    # If still awaiting start, don't process the stale snapshot
    if trace.awaiting_start? do
      panels = %{
        thinking: "",
        usage: %{},
        conversation: [],
        config: %{status: :idle, iteration: 0}
      }

      {trace, messages, panels}
    else
      trace =
        if current_iteration > trace.last_iteration and trace.last_iteration > 0 do
          %{trace | last_iteration: current_iteration, text: "", thinking: ""}
        else
          %{trace | last_iteration: max(current_iteration, trace.last_iteration)}
        end

      {messages, trace} = sync_tool_calls(messages, tool_calls, trace)

      messages = update_pending_content(messages, streaming_text)

      {messages, trace} =
        if snap.done? do
          final_content = snap.result || streaming_text
          messages = finalize_pending(messages, final_content, trace.thinking)
          {messages, trace}
        else
          trace = %{trace | text: streaming_text, thinking: streaming_thinking}
          {messages, trace}
        end

      panels = %{
        thinking: streaming_thinking,
        usage: details[:usage] || %{},
        conversation: details[:conversation] || [],
        config: %{
          model: details[:model],
          max_iterations: details[:max_iterations],
          available_tools: details[:available_tools] || [],
          current_llm_call_id: details[:current_llm_call_id],
          iteration: current_iteration,
          duration_ms: details[:duration_ms],
          termination_reason: details[:termination_reason],
          status: snap.status
        }
      }

      {trace, messages, panels}
    end
  end

  defp sync_tool_calls(messages, [], trace), do: {messages, trace}

  defp sync_tool_calls(messages, tool_calls, trace) do
    {messages, seen, completed} =
      Enum.reduce(tool_calls, {messages, trace.seen_tool_ids, trace.completed_tool_ids}, fn tc,
                                                                                            {msgs,
                                                                                             seen,
                                                                                             completed} ->
        if MapSet.member?(seen, tc.id) do
          msgs = update_tool_call(msgs, tc)

          completed =
            if tc.status == :completed, do: MapSet.put(completed, tc.id), else: completed

          {msgs, seen, completed}
        else
          tool_msg = %{
            id: tc.id,
            role: :tool_call,
            tool_name: tc.name,
            arguments: tc.arguments,
            status: tc.status,
            result: tc.result
          }

          msgs = insert_before_pending(msgs, tool_msg)
          seen = MapSet.put(seen, tc.id)

          completed =
            if tc.status == :completed, do: MapSet.put(completed, tc.id), else: completed

          {msgs, seen, completed}
        end
      end)

    trace = %{trace | seen_tool_ids: seen, completed_tool_ids: completed}
    {messages, trace}
  end

  defp update_tool_call(messages, tc) do
    Enum.map(messages, fn msg ->
      if msg[:id] == tc.id do
        %{msg | status: tc.status, result: tc.result}
      else
        msg
      end
    end)
  end

  defp insert_before_pending(messages, new_msg) do
    case Enum.split_while(messages, &(!&1[:pending])) do
      {before, [pending | rest]} -> before ++ [new_msg, pending | rest]
      {all, []} -> all ++ [new_msg]
    end
  end

  defp update_pending_content(messages, content) do
    Enum.map(messages, fn msg ->
      if msg[:pending], do: %{msg | content: content}, else: msg
    end)
  end

  defp finalize_pending(messages, content, reasoning) do
    Enum.map(messages, fn msg ->
      if msg[:pending] do
        msg
        |> Map.put(:content, content)
        |> Map.put(:reasoning, reasoning)
        |> Map.delete(:pending)
      else
        msg
      end
    end)
  end

  defp gen_id, do: System.unique_integer([:positive]) |> Integer.to_string()

  defp render_markdown(content) when is_binary(content) and content != "" do
    case MDEx.to_html(content) do
      {:ok, html} -> html
      {:error, _} -> content
    end
  end

  defp render_markdown(_), do: ""

  defp format_args(nil), do: ""

  defp format_args(args) when is_map(args) do
    args
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
    |> String.slice(0, 80)
  end

  defp format_args(args), do: inspect(args) |> String.slice(0, 80)

  defp format_result(nil), do: nil
  defp format_result({:ok, result}), do: inspect(result, limit: 5, printable_limit: 100)
  defp format_result({:error, reason}), do: "Error: #{inspect(reason)}"
  defp format_result(result), do: inspect(result, limit: 5, printable_limit: 100)

  defp format_conversation_content(msg) do
    content = msg[:content] || ""

    cond do
      msg[:tool_calls] ->
        tool_names = Enum.map(msg[:tool_calls], & &1[:name]) |> Enum.join(", ")
        "Calling: #{tool_names}"

      msg[:role] == :tool ->
        name = msg[:name] || "unknown"
        "[#{name}] #{String.slice(to_string(content), 0, 200)}"

      msg[:role] == :system ->
        String.slice(to_string(content), 0, 150) <> "..."

      true ->
        to_string(content)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="space-y-6 max-w-7xl mx-auto">
        <.header>
          AI Chat Agent Demo
          <:subtitle>Jido.AI.Agent with streaming, tool calls, and full observability</:subtitle>
        </.header>

        <%!-- Error Display --%>
        <%= if @error do %>
          <div class="alert alert-error">
            <span>{@error}</span>
            <button phx-click="restart_agent" class="btn btn-sm">Restart Agent</button>
          </div>
        <% end %>

        <%!-- Full Width Chat Section --%>
        <div class="card bg-base-200 shadow-lg">
          <div class="card-body">
            <%!-- Messages --%>
            <div
              id="messages"
              class="h-[400px] overflow-y-auto space-y-3 mb-4"
              phx-hook="ScrollBottom"
            >
              <%= if @messages == [] do %>
                <div class="text-center text-base-content/50 py-8">
                  <p class="text-lg">Start a conversation</p>
                  <p class="text-sm mt-2">
                    Try: "What is 15 * 23?" or "What's the weather in Chicago?"
                  </p>
                </div>
              <% else %>
                <%= for msg <- @messages do %>
                  <%= if msg.role == :tool_call do %>
                    <div class="flex items-center gap-2 px-4 py-2 bg-base-300 rounded-lg text-sm max-w-2xl mx-auto">
                      <span class={[
                        "badge badge-sm",
                        msg.status == :running && "badge-warning",
                        msg.status == :completed && "badge-success",
                        msg.status == :failed && "badge-error"
                      ]}>
                        <%= case msg.status do %>
                          <% :running -> %>
                            <span class="loading loading-spinner loading-xs mr-1"></span>
                          <% :completed -> %>
                            ✓
                          <% _ -> %>
                            ✗
                        <% end %>
                      </span>
                      <span class="font-mono font-semibold text-primary">{msg.tool_name}</span>
                      <span class="opacity-60">({format_args(msg.arguments)})</span>
                      <%= if msg.result do %>
                        <span class="opacity-70">→ {format_result(msg.result)}</span>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if msg.role in [:user, :assistant] do %>
                    <div class={["chat", (msg.role == :user && "chat-end") || "chat-start"]}>
                      <div class="chat-header text-xs opacity-70 mb-1">
                        {if msg.role == :user, do: "You", else: "Assistant"}
                      </div>
                      <div class={[
                        "chat-bubble max-w-2xl",
                        (msg.role == :user && "chat-bubble-primary") || "chat-bubble-neutral"
                      ]}>
                        <%= if msg[:pending] == true and msg.content == "" do %>
                          <span class="loading loading-dots loading-sm"></span>
                        <% else %>
                          <%= if msg[:reasoning] && msg.reasoning != "" do %>
                            <details class="collapse collapse-arrow bg-base-300/30 mb-2 -mx-2 -mt-1 rounded">
                              <summary class="collapse-title text-xs font-medium min-h-0 py-1 px-2">
                                💭 Reasoning
                              </summary>
                              <div class="collapse-content px-2 pb-2">
                                <pre class="text-xs whitespace-pre-wrap opacity-70 m-0">{msg.reasoning}</pre>
                              </div>
                            </details>
                          <% end %>
                          <div class="prose prose-sm max-w-none">
                            {raw(render_markdown(msg.content))}
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
            </div>

            <%!-- Input Form --%>
            <form phx-submit="send" class="flex gap-2">
              <input
                type="text"
                name="input"
                value={@input}
                phx-change="update_input"
                placeholder="Type a message..."
                class="input input-bordered flex-1"
                disabled={@running? or is_nil(@agent_pid)}
                autocomplete="off"
                id="chat-input"
              />
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@running? or is_nil(@agent_pid) or String.trim(@input) == ""}
              >
                <%= if @running? do %>
                  <span class="loading loading-spinner loading-sm"></span>
                <% else %>
                  Send
                <% end %>
              </button>
            </form>
          </div>
        </div>

        <%!-- Debug Panels Grid --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <%!-- Agent Status Panel --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body p-4">
              <h3 class="font-semibold text-sm mb-2">Agent Status</h3>
              <dl class="text-xs space-y-1">
                <div class="flex justify-between">
                  <dt class="opacity-70">Status</dt>
                  <dd class={[
                    "font-medium",
                    @panels.config[:status] == :success && "text-success",
                    @panels.config[:status] == :failure && "text-error",
                    @panels.config[:status] == :running && "text-warning"
                  ]}>
                    {@panels.config[:status] || "idle"}
                  </dd>
                </div>
                <%= if @panels.config[:iteration] do %>
                  <div class="flex justify-between">
                    <dt class="opacity-70">Iteration</dt>
                    <dd>{@panels.config[:iteration]} / {@panels.config[:max_iterations] || "?"}</dd>
                  </div>
                <% end %>
                <%= if @panels.config[:model] do %>
                  <div class="flex justify-between">
                    <dt class="opacity-70">Model</dt>
                    <dd class="font-mono text-xs truncate max-w-32">{@panels.config[:model]}</dd>
                  </div>
                <% end %>
                <%= if @panels.config[:duration_ms] do %>
                  <div class="flex justify-between">
                    <dt class="opacity-70">Duration</dt>
                    <dd>{@panels.config[:duration_ms]}ms</dd>
                  </div>
                <% end %>
                <%= if @panels.config[:termination_reason] do %>
                  <div class="flex justify-between">
                    <dt class="opacity-70">Termination</dt>
                    <dd>{@panels.config[:termination_reason]}</dd>
                  </div>
                <% end %>
              </dl>
            </div>
          </div>

          <%!-- Token Usage Panel --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body p-4">
              <h3 class="font-semibold text-sm mb-2">Token Usage</h3>
              <dl class="text-xs space-y-1">
                <div class="flex justify-between">
                  <dt class="opacity-70">Input</dt>
                  <dd>{@panels.usage[:input_tokens] || 0}</dd>
                </div>
                <div class="flex justify-between">
                  <dt class="opacity-70">Output</dt>
                  <dd>{@panels.usage[:output_tokens] || 0}</dd>
                </div>
                <%= if @panels.usage[:cache_read_input_tokens] do %>
                  <div class="flex justify-between">
                    <dt class="opacity-70">Cache Read</dt>
                    <dd>{@panels.usage[:cache_read_input_tokens]}</dd>
                  </div>
                <% end %>
              </dl>
            </div>
          </div>

          <%!-- Available Tools Panel --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body p-4">
              <h3 class="font-semibold text-sm mb-2">Available Tools</h3>
              <div class="flex flex-wrap gap-1">
                <%= for tool <- @panels.config[:available_tools] || [] do %>
                  <span class="badge badge-sm badge-outline font-mono">{tool}</span>
                <% end %>
                <%= if (@panels.config[:available_tools] || []) == [] do %>
                  <span class="text-xs opacity-50">No tools loaded</span>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Thinking Panel --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body p-4">
              <h3 class="font-semibold text-sm mb-2 flex items-center gap-2">
                Thinking
                <%= if @panels.thinking != "" do %>
                  <span class="loading loading-dots loading-xs"></span>
                <% end %>
              </h3>
              <%= if @panels.thinking != "" do %>
                <pre class="text-xs whitespace-pre-wrap opacity-70 max-h-32 overflow-y-auto">{@panels.thinking}</pre>
              <% else %>
                <span class="text-xs opacity-50">No active thinking</span>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Full Width Conversation History --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body p-4">
            <h3 class="font-semibold text-sm mb-2">
              Full Conversation History ({length(@conversation_history)} messages)
            </h3>
            <div class="text-xs space-y-2 max-h-64 overflow-y-auto">
              <%= if @conversation_history == [] do %>
                <span class="opacity-50">No conversation yet</span>
              <% else %>
                <%= for msg <- @conversation_history do %>
                  <div class={[
                    "p-2 rounded",
                    msg[:role] == :system && "bg-base-300",
                    msg[:role] == :user && "bg-primary/20",
                    msg[:role] == :assistant && "bg-neutral/20",
                    msg[:role] == :tool && "bg-info/20"
                  ]}>
                    <div class="font-semibold opacity-70 flex justify-between">
                      <span>{msg[:role]}</span>
                      <%= if msg[:tool_calls] do %>
                        <span class="badge badge-xs">tool_calls</span>
                      <% end %>
                    </div>
                    <pre class="whitespace-pre-wrap text-xs mt-1 opacity-90">{format_conversation_content(msg)}</pre>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
