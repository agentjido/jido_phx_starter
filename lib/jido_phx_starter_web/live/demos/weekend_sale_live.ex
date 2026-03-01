defmodule JidoPhxStarterWeb.Demos.WeekendSaleLive do
  @moduledoc """
  Demo: Multi-Agent Weekend Sale Orchestration

  Demonstrates Jido's native multi-agent patterns with full observability:
  - Orchestrator spawning specialist children in parallel
  - Real-time status visualization of agent coordination
  - Fan-in of specialist results into unified plan
  - Plan review and execution workflow
  """
  use JidoPhxStarterWeb, :live_view

  alias JidoPhxStarter.Demos.MultiAgent.OrchestratorAgent
  alias JidoPhxStarter.Demos.ListingsDomain
  alias JidoPhxStarter.Demos.ListingsDomain.Listing

  @default_actor %{id: "00000000-0000-0000-0000-000000000001", role: :user}

  @poll_interval 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:agent_pid, nil)
      |> assign(:running?, false)
      |> assign(:status, :idle)
      |> assign(:error, nil)
      |> assign(:config, %{discount_percent: 20, use_llm: true})
      |> assign(:specialists, %{pending: [], results: %{}})
      |> assign(:plan, %{})
      |> assign(:execution_results, nil)
      |> assign(:poll_ref, nil)
      |> assign(:highlight_keys, MapSet.new())
      |> stream(:timeline, [])
      |> stream(:listings, [])

    if connected?(socket) do
      socket = seed_listings(socket)

      case start_agent() do
        {:ok, pid} ->
          Process.monitor(pid)

          socket =
            socket
            |> assign(:agent_pid, pid)
            |> add_timeline_event(:info, "orchestrator", "Orchestrator agent started")

          {:ok, socket}

        {:error, reason} ->
          {:ok, assign(socket, :error, "Failed to start agent: #{inspect(reason)}")}
      end
    else
      {:ok, socket}
    end
  end

  defp start_agent do
    Jido.AgentServer.start_link(
      agent: OrchestratorAgent,
      id: "orchestrator-#{System.unique_integer([:positive])}",
      jido: JidoPhxStarter.Jido
    )
  end

  defp seed_listings(socket) do
    listings_data = [
      %{title: "Vintage Baseball Card - 1952 Topps", price: "150.00", quantity: 1},
      %{title: "Pokemon Charizard 1st Edition", price: "500.00", quantity: 1},
      %{title: "Magic: The Gathering Black Lotus", price: "1000.00", quantity: 1},
      %{title: "Rare Coin Collection (5 coins)", price: "75.00", quantity: 1},
      %{title: "Comic Book - Action Comics #1 Reprint", price: "25.00", quantity: 3}
    ]

    ash_context = %{domain: ListingsDomain, actor: @default_actor}

    Enum.reduce(listings_data, socket, fn params, acc ->
      case Listing.Jido.Create.run(params, ash_context) do
        {:ok, listing} ->
          stream_insert(acc, :listings, %{id: get_listing_id(listing), data: listing})

        {:error, _} ->
          acc
      end
    end)
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    :ok
  end

  @impl true
  def handle_event("update_discount", %{"discount" => discount}, socket) do
    discount_int = String.to_integer(discount)
    config = Map.put(socket.assigns.config, :discount_percent, discount_int)
    {:noreply, assign(socket, :config, config)}
  end

  def handle_event("toggle_llm", _params, socket) do
    config = Map.update!(socket.assigns.config, :use_llm, &(!&1))
    {:noreply, assign(socket, :config, config)}
  end

  def handle_event("prepare_sale", _params, socket) do
    if socket.assigns.running? or is_nil(socket.assigns.agent_pid) do
      {:noreply, socket}
    else
      %{discount_percent: discount, use_llm: use_llm} = socket.assigns.config

      signal =
        Jido.Signal.new!(
          "sale.prepare",
          %{discount_percent: discount, use_llm: use_llm},
          source: "/live"
        )

      :ok = Jido.AgentServer.cast(socket.assigns.agent_pid, signal)

      {:noreply,
       socket
       |> assign(:running?, true)
       |> assign(:status, :collecting)
       |> assign(:specialists, %{pending: [:listings, :recommendations, :support], results: %{}})
       |> assign(:plan, %{})
       |> assign(:execution_results, nil)
       |> assign(:highlight_keys, MapSet.new())
       |> add_timeline_event(:info, "orchestrator", "Preparing #{discount}% off sale...")
       |> add_timeline_event(:spawn, "orchestrator", "Spawning 3 specialists in parallel")
       |> schedule_poll()}
    end
  end

  def handle_event("execute_plan", _params, socket) do
    if socket.assigns.status != :ready or is_nil(socket.assigns.agent_pid) do
      {:noreply, socket}
    else
      signal = Jido.Signal.new!("sale.execute", %{}, source: "/live")
      :ok = Jido.AgentServer.cast(socket.assigns.agent_pid, signal)

      {:noreply,
       socket
       |> assign(:running?, true)
       |> assign(:status, :executing)
       |> add_timeline_event(:info, "orchestrator", "Executing approved plan...")
       |> schedule_poll()}
    end
  end

  def handle_event("restart_agent", _params, socket) do
    if pid = socket.assigns[:agent_pid] do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end

    case start_agent() do
      {:ok, pid} ->
        Process.monitor(pid)

        socket = seed_listings(socket)

        {:noreply,
         socket
         |> assign(:agent_pid, pid)
         |> assign(:error, nil)
         |> assign(:running?, false)
         |> assign(:status, :idle)
         |> assign(:specialists, %{pending: [], results: %{}})
         |> assign(:plan, %{})
         |> assign(:execution_results, nil)
         |> stream(:timeline, [], reset: true)
         |> add_timeline_event(:info, "orchestrator", "Agent restarted")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to restart: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:poll, ref}, %{assigns: %{poll_ref: ref}} = socket) do
    socket = assign(socket, :poll_ref, nil)

    if socket.assigns.running? and socket.assigns.agent_pid do
      case Jido.AgentServer.state(socket.assigns.agent_pid) do
        {:ok, server_state} ->
          agent_state = server_state.agent.state
          socket = process_state_update(socket, agent_state)

          if agent_state.status in [:ready, :done] do
            {:noreply, assign(socket, :running?, false)}
          else
            {:noreply, schedule_poll(socket)}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:running?, false)
           |> assign(:error, "State error: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll, _old_ref}, socket), do: {:noreply, socket}

  def handle_info({:clear_highlight, key}, socket) do
    {:noreply, assign(socket, :highlight_keys, MapSet.delete(socket.assigns.highlight_keys, key))}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, socket) do
    if pid == socket.assigns.agent_pid do
      {:noreply,
       socket
       |> assign(:agent_pid, nil)
       |> assign(:running?, false)
       |> assign(:error, "Agent crashed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  defp schedule_poll(socket) do
    ref = make_ref()
    Process.send_after(self(), {:poll, ref}, @poll_interval)
    assign(socket, :poll_ref, ref)
  end

  defp process_state_update(socket, agent_state) do
    current_results = socket.assigns.specialists.results
    new_results = agent_state.specialist_results || %{}

    socket =
      Enum.reduce(Map.keys(new_results) -- Map.keys(current_results), socket, fn specialist,
                                                                                 acc ->
        result = Map.get(new_results, specialist)

        acc
        |> add_timeline_event(:success, to_string(specialist), result.summary)
        |> highlight_specialist(specialist)
      end)

    socket =
      if agent_state.status == :ready and socket.assigns.status != :ready do
        socket
        |> add_timeline_event(:success, "orchestrator", "All specialists complete - plan merged")
        |> assign(:highlight_keys, MapSet.put(socket.assigns.highlight_keys, :plan))
        |> tap(fn _ -> Process.send_after(self(), {:clear_highlight, :plan}, 2000) end)
      else
        socket
      end

    socket =
      if agent_state.status == :done and socket.assigns.status != :done do
        exec_results = agent_state.execution_results || %{}
        executed_count = length(exec_results[:executed] || [])
        error_count = length(exec_results[:errors] || [])

        socket
        |> assign(:execution_results, exec_results)
        |> add_timeline_event(
          if(error_count > 0, do: :warning, else: :success),
          "orchestrator",
          "Executed #{executed_count} actions" <>
            if(error_count > 0, do: " (#{error_count} errors)", else: "")
        )
      else
        socket
      end

    socket
    |> assign(:status, agent_state.status || :idle)
    |> assign(:specialists, %{
      pending: agent_state.pending_specialists || [],
      results: new_results
    })
    |> assign(:plan, agent_state.plan || %{})
  end

  defp highlight_specialist(socket, specialist) do
    socket =
      assign(socket, :highlight_keys, MapSet.put(socket.assigns.highlight_keys, specialist))

    Process.send_after(self(), {:clear_highlight, specialist}, 1500)
    socket
  end

  defp add_timeline_event(socket, level, source, message) do
    event = %{
      id: System.unique_integer([:positive]),
      ts: DateTime.utc_now(),
      level: level,
      source: source,
      message: message
    }

    stream_insert(socket, :timeline, event, at: 0)
  end

  defp get_listing_id(%{id: id}), do: id
  defp get_listing_id(%{"id" => id}), do: id
  defp get_listing_id(_), do: "unknown-#{System.unique_integer([:positive])}"

  defp specialist_state(specialist, assigns) do
    cond do
      Map.has_key?(assigns.specialists.results, specialist) -> :done
      specialist in assigns.specialists.pending -> :running
      true -> :idle
    end
  end

  defp specialist_result(specialist, assigns) do
    Map.get(assigns.specialists.results, specialist)
  end

  defp progress_percent(assigns) do
    completed = map_size(assigns.specialists.results)
    round(completed / 3 * 100)
  end

  defp status_label(status) do
    case status do
      :idle -> "Idle"
      :collecting -> "Collecting"
      :ready -> "Ready"
      :executing -> "Executing"
      :done -> "Done"
      _ -> "Unknown"
    end
  end

  defp status_class(status) do
    case status do
      :idle -> "badge-ghost"
      :collecting -> "badge-warning"
      :ready -> "badge-success"
      :executing -> "badge-info"
      :done -> "badge-success"
      _ -> "badge-ghost"
    end
  end

  defp level_class(level) do
    case level do
      :info -> "text-info"
      :success -> "text-success"
      :warning -> "text-warning"
      :error -> "text-error"
      :spawn -> "text-secondary"
      _ -> "text-base-content"
    end
  end

  defp level_icon(level) do
    case level do
      :info -> "hero-information-circle"
      :success -> "hero-check-circle"
      :warning -> "hero-exclamation-triangle"
      :error -> "hero-x-circle"
      :spawn -> "hero-arrow-path"
      _ -> "hero-arrow-right"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="space-y-6 max-w-7xl mx-auto">
        <%!-- Header with Status --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Multi-Agent Weekend Sale</h1>
            <p class="text-base-content/60 text-sm">Orchestrated marketplace operations demo</p>
          </div>
          <div class="flex items-center gap-4">
            <div class={"badge badge-lg #{status_class(@status)}"}>
              <%= if @status == :collecting or @status == :executing do %>
                <span class="loading loading-spinner loading-xs mr-2"></span>
              <% end %>
              {status_label(@status)}
            </div>
            <button phx-click="restart_agent" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-path" class="w-4 h-4" /> Reset
            </button>
          </div>
        </div>

        <%!-- Error Display --%>
        <%= if @error do %>
          <div class="alert alert-error">
            <.icon name="hero-exclamation-circle" class="w-5 h-5" />
            <span>{@error}</span>
          </div>
        <% end %>

        <%!-- Progress Bar --%>
        <%= if @status == :collecting do %>
          <div class="w-full">
            <div class="flex justify-between text-xs text-base-content/60 mb-1">
              <span>Specialist Progress</span>
              <span>{progress_percent(assigns)}%</span>
            </div>
            <progress
              class="progress progress-primary w-full"
              value={progress_percent(assigns)}
              max="100"
            >
            </progress>
          </div>
        <% end %>

        <%!-- Main Grid --%>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <%!-- Left Column: Architecture + Specialists --%>
          <div class="lg:col-span-7 space-y-4">
            <%!-- Architecture Visualization Card --%>
            <div class="card bg-gradient-to-br from-base-200 to-base-300/40 shadow-xl border border-base-300">
              <div class="card-body">
                <h2 class="card-title text-sm font-semibold mb-4">
                  <.icon name="hero-cube-transparent" class="w-5 h-5" /> Agent Architecture
                </h2>

                <div class="flex flex-col items-center gap-6">
                  <%!-- Orchestrator Node --%>
                  <div class={[
                    "relative flex flex-col items-center justify-center w-32 h-32 rounded-full",
                    "bg-base-100 border-4 transition-all duration-300",
                    @status == :idle && "border-base-300",
                    @status in [:collecting, :executing] &&
                      "border-warning ring ring-warning/30 ring-offset-2 ring-offset-base-200",
                    @status in [:ready, :done] &&
                      "border-success ring ring-success/30 ring-offset-2 ring-offset-base-200"
                  ]}>
                    <.icon name="hero-cpu-chip" class="w-8 h-8 mb-1" />
                    <span class="font-semibold text-sm">Orchestrator</span>
                    <span class={"badge badge-xs mt-1 #{status_class(@status)}"}>
                      {status_label(@status)}
                    </span>
                  </div>

                  <%!-- Connection Lines --%>
                  <div class="flex items-center gap-4 -my-2">
                    <%= for specialist <- [:listings, :recommendations, :support] do %>
                      <div class={[
                        "w-1 h-8 rounded transition-colors duration-300",
                        specialist_state(specialist, assigns) == :idle && "bg-base-300",
                        specialist_state(specialist, assigns) == :running &&
                          "bg-warning animate-pulse",
                        specialist_state(specialist, assigns) == :done && "bg-success"
                      ]}>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Specialist Nodes --%>
                  <div class="flex items-start gap-4">
                    <%= for {specialist, icon, label} <- [
                      {:listings, "hero-tag", "Listings"},
                      {:recommendations, "hero-light-bulb", "Recomm."},
                      {:support, "hero-chat-bubble-left-right", "Support"}
                    ] do %>
                      <div class={[
                        "flex flex-col items-center justify-center w-20 h-20 rounded-xl",
                        "bg-base-100 border-2 transition-all duration-300",
                        specialist_state(specialist, assigns) == :idle && "border-base-300",
                        specialist_state(specialist, assigns) == :running && "border-warning",
                        specialist_state(specialist, assigns) == :done && "border-success",
                        MapSet.member?(@highlight_keys, specialist) && "ring-2 ring-success/50"
                      ]}>
                        <.icon name={icon} class="w-5 h-5 mb-1" />
                        <span class="text-xs font-medium">{label}</span>
                        <%= case specialist_state(specialist, assigns) do %>
                          <% :running -> %>
                            <span class="loading loading-spinner loading-xs mt-1"></span>
                          <% :done -> %>
                            <.icon name="hero-check" class="w-4 h-4 text-success mt-1" />
                          <% _ -> %>
                            <span class="w-4 h-4 mt-1"></span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Specialist Result Cards --%>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <%= for {specialist, icon, title} <- [
                {:listings, "hero-tag", "Listings Analysis"},
                {:recommendations, "hero-light-bulb", "Bundle Ideas"},
                {:support, "hero-chat-bubble-left-right", "Announcement"}
              ] do %>
                <div class={[
                  "card bg-base-200 shadow transition-all duration-500",
                  MapSet.member?(@highlight_keys, specialist) &&
                    "bg-success/10 ring-2 ring-success/30"
                ]}>
                  <div class="card-body p-4">
                    <h3 class="font-semibold text-sm flex items-center gap-2">
                      <.icon name={icon} class="w-4 h-4" />
                      {title}
                    </h3>
                    <%= if result = specialist_result(specialist, assigns) do %>
                      <p class="text-xs text-base-content/70 line-clamp-2">{result.summary}</p>
                      <div class="flex items-center gap-2 mt-2">
                        <span class="badge badge-xs badge-primary">
                          {length(result.actions)} actions
                        </span>
                        <span class="text-xs text-base-content/50">
                          {round(result.confidence * 100)}% confident
                        </span>
                      </div>
                    <% else %>
                      <p class="text-xs text-base-content/40 italic">
                        <%= if specialist in @specialists.pending do %>
                          Analyzing...
                        <% else %>
                          Waiting to start
                        <% end %>
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Right Column: Config + Plan --%>
          <div class="lg:col-span-5 space-y-4">
            <%!-- Configuration Card --%>
            <div class="card bg-base-200 shadow">
              <div class="card-body p-4">
                <h2 class="card-title text-sm font-semibold mb-3">
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5" /> Configuration
                </h2>

                <div class="space-y-4">
                  <div>
                    <label class="label py-1">
                      <span class="label-text text-xs">Discount Percentage</span>
                      <span class="label-text-alt font-mono">{@config.discount_percent}%</span>
                    </label>
                    <input
                      type="range"
                      min="5"
                      max="50"
                      step="5"
                      value={@config.discount_percent}
                      phx-change="update_discount"
                      name="discount"
                      class="range range-primary range-sm"
                      disabled={@running?}
                    />
                    <div class="w-full flex justify-between text-xs px-1 mt-1">
                      <span>5%</span>
                      <span>25%</span>
                      <span>50%</span>
                    </div>
                  </div>

                  <div class="form-control">
                    <label class="label cursor-pointer py-1">
                      <span class="label-text text-xs">Use LLM for announcements</span>
                      <input
                        type="checkbox"
                        class="toggle toggle-primary toggle-sm"
                        checked={@config.use_llm}
                        phx-click="toggle_llm"
                        disabled={@running?}
                      />
                    </label>
                  </div>

                  <button
                    phx-click="prepare_sale"
                    class="btn btn-primary w-full"
                    disabled={@running? or is_nil(@agent_pid)}
                  >
                    <%= if @status == :collecting do %>
                      <span class="loading loading-spinner loading-sm"></span> Preparing...
                    <% else %>
                      <.icon name="hero-rocket-launch" class="w-5 h-5" /> Prepare Sale
                    <% end %>
                  </button>
                </div>
              </div>
            </div>

            <%!-- Merged Plan Card --%>
            <div class={[
              "card bg-base-200 shadow transition-all duration-500",
              MapSet.member?(@highlight_keys, :plan) && "ring-2 ring-success/50 bg-success/5"
            ]}>
              <div class="card-body p-4">
                <h2 class="card-title text-sm font-semibold mb-3">
                  <.icon name="hero-clipboard-document-list" class="w-5 h-5" /> Merged Plan
                  <%= if @status == :ready do %>
                    <span class="badge badge-success badge-sm ml-auto">Ready</span>
                  <% end %>
                </h2>

                <%= if @plan == %{} do %>
                  <div class="text-center py-6 text-base-content/40">
                    <.icon name="hero-document-text" class="w-8 h-8 mx-auto mb-2" />
                    <p class="text-sm">Run "Prepare Sale" to generate a plan</p>
                  </div>
                <% else %>
                  <div class="space-y-3 text-sm">
                    <%!-- Price Updates --%>
                    <%= if (pu = @plan[:price_updates] || []) != [] do %>
                      <div>
                        <h4 class="font-medium text-xs text-base-content/60 mb-1">
                          Price Updates ({length(pu)})
                        </h4>
                        <div class="max-h-32 overflow-y-auto space-y-1">
                          <%= for action <- pu do %>
                            <div class="flex justify-between text-xs bg-base-300/50 rounded px-2 py-1">
                              <span class="truncate max-w-[60%]">{action[:listing_id]}</span>
                              <span class="text-success">
                                ${action[:current_price]} → ${action[:new_price]}
                              </span>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Bundle Suggestions --%>
                    <%= if (bundles = @plan[:bundle_suggestions] || []) != [] do %>
                      <div>
                        <h4 class="font-medium text-xs text-base-content/60 mb-1">
                          Bundle Suggestions ({length(bundles)})
                        </h4>
                        <%= for bundle <- bundles do %>
                          <div class="flex items-center gap-2 text-xs">
                            <span class="badge badge-xs badge-secondary">
                              +{bundle[:discount_boost]}%
                            </span>
                            <span>{bundle[:suggestion]}</span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <%!-- Announcement --%>
                    <%= if announcement = @plan[:announcement] do %>
                      <div>
                        <h4 class="font-medium text-xs text-base-content/60 mb-1">Announcement</h4>
                        <div class="bg-base-300/50 rounded p-2">
                          <p class="font-semibold text-xs">{announcement[:title]}</p>
                          <p class="text-xs text-base-content/60">
                            Channels: {Enum.join(announcement[:channels] || [], ", ")}
                          </p>
                        </div>
                      </div>
                    <% end %>

                    <%!-- Questions --%>
                    <%= if (questions = @plan[:all_questions] || []) != [] do %>
                      <div class="alert alert-info py-2">
                        <.icon name="hero-question-mark-circle" class="w-4 h-4" />
                        <div class="text-xs">
                          <span class="font-medium">{length(questions)} questions for you</span>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Execute Button --%>
                  <button
                    phx-click="execute_plan"
                    class="btn btn-success w-full mt-4"
                    disabled={@status != :ready}
                  >
                    <%= if @status == :executing do %>
                      <span class="loading loading-spinner loading-sm"></span> Executing...
                    <% else %>
                      <.icon name="hero-play" class="w-5 h-5" /> Execute Plan
                    <% end %>
                  </button>
                <% end %>

                <%!-- Execution Results --%>
                <%= if @execution_results do %>
                  <div class="mt-4 pt-4 border-t border-base-300">
                    <h4 class="font-medium text-xs text-base-content/60 mb-2">Execution Results</h4>
                    <div class="flex gap-4">
                      <div class="stat bg-success/10 rounded p-2">
                        <div class="stat-value text-lg text-success">
                          {length(@execution_results[:executed] || [])}
                        </div>
                        <div class="stat-desc text-xs">Executed</div>
                      </div>
                      <%= if (@execution_results[:errors] || []) != [] do %>
                        <div class="stat bg-error/10 rounded p-2">
                          <div class="stat-value text-lg text-error">
                            {length(@execution_results[:errors])}
                          </div>
                          <div class="stat-desc text-xs">Errors</div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Timeline Panel --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body p-4">
            <h2 class="card-title text-sm font-semibold mb-3">
              <.icon name="hero-clock" class="w-5 h-5" /> Event Timeline
            </h2>
            <div id="timeline" phx-update="stream" class="space-y-1 max-h-48 overflow-y-auto">
              <div
                :for={{id, event} <- @streams.timeline}
                id={id}
                class="flex items-start gap-2 text-xs"
              >
                <span class="text-base-content/40 font-mono whitespace-nowrap">
                  {Calendar.strftime(event.ts, "%H:%M:%S")}
                </span>
                <.icon
                  name={level_icon(event.level)}
                  class={"w-4 h-4 flex-shrink-0 #{level_class(event.level)}"}
                />
                <span class="font-medium text-base-content/60">[{event.source}]</span>
                <span class="text-base-content/80">{event.message}</span>
              </div>
              <div class="hidden only:block text-base-content/40 text-sm py-4 text-center">
                No events yet
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
