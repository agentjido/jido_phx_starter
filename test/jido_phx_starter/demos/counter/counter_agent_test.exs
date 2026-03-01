defmodule JidoPhxStarter.Demos.CounterAgentTest do
  use ExUnit.Case, async: true

  alias JidoPhxStarter.Demos.CounterAgent
  alias JidoPhxStarter.Demos.Counter.{IncrementAction, DecrementAction, ResetAction}
  alias Jido.Signal

  describe "CounterAgent" do
    test "creates agent with default count of 0" do
      agent = CounterAgent.new()
      assert agent.state.count == 0
    end

    test "increment action increases count" do
      agent = CounterAgent.new()
      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{by: 1}})
      assert agent.state.count == 1
    end

    test "increment action with custom amount" do
      agent = CounterAgent.new()
      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{by: 5}})
      assert agent.state.count == 5
    end

    test "decrement action decreases count" do
      agent = CounterAgent.new()
      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{by: 10}})
      {agent, []} = CounterAgent.cmd(agent, {DecrementAction, %{by: 3}})
      assert agent.state.count == 7
    end

    test "reset action sets count to 0" do
      agent = CounterAgent.new()
      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{by: 100}})
      {agent, []} = CounterAgent.cmd(agent, ResetAction)
      assert agent.state.count == 0
    end

    test "chaining multiple actions" do
      agent = CounterAgent.new()

      {agent, []} =
        CounterAgent.cmd(agent, [
          {IncrementAction, %{by: 10}},
          {DecrementAction, %{by: 3}},
          {IncrementAction, %{by: 5}}
        ])

      assert agent.state.count == 12
    end
  end

  describe "AgentServer with signals" do
    test "processes increment signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: CounterAgent,
          id: "test-counter",
          jido: JidoPhxStarter.Jido
        )

      signal = Signal.new!("counter.increment", %{by: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.count == 5
      GenServer.stop(pid)
    end

    test "processes decrement signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: CounterAgent,
          id: "test-counter-2",
          jido: JidoPhxStarter.Jido
        )

      inc_signal = Signal.new!("counter.increment", %{by: 10}, source: "/test")
      {:ok, _} = Jido.AgentServer.call(pid, inc_signal)

      dec_signal = Signal.new!("counter.decrement", %{by: 4}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, dec_signal)

      assert agent.state.count == 6
      GenServer.stop(pid)
    end

    test "processes reset signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: CounterAgent,
          id: "test-counter-3",
          jido: JidoPhxStarter.Jido
        )

      inc_signal = Signal.new!("counter.increment", %{by: 100}, source: "/test")
      {:ok, _} = Jido.AgentServer.call(pid, inc_signal)

      reset_signal = Signal.new!("counter.reset", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, reset_signal)

      assert agent.state.count == 0
      GenServer.stop(pid)
    end
  end
end
