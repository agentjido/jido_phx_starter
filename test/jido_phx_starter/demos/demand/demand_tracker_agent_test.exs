defmodule JidoPhxStarter.Demos.DemandTrackerAgentTest do
  use ExUnit.Case, async: true

  alias JidoPhxStarter.Demos.DemandTrackerAgent

  alias JidoPhxStarter.Demos.Demand.{
    BoostAction,
    CoolAction,
    DecayAction,
    ToggleAutoDecayAction
  }

  alias Jido.Signal
  alias Jido.Agent.Directive

  describe "DemandTrackerAgent" do
    test "creates agent with default demand of 50" do
      agent = DemandTrackerAgent.new()
      assert agent.state.demand == 50
      assert agent.state.ticks == 0
      assert agent.state.auto_decay_enabled == false
    end

    test "boost action increases demand and emits directive" do
      agent = DemandTrackerAgent.new()
      {agent, directives} = DemandTrackerAgent.cmd(agent, {BoostAction, %{amount: 10}})

      assert agent.state.demand == 60
      assert agent.state.last_updated_at != nil
      assert length(directives) == 1
      assert %Directive.Emit{signal: %Signal{type: "listing.demand.changed"}} = hd(directives)
    end

    test "boost action clamps demand at 100" do
      agent = DemandTrackerAgent.new()
      {agent, _} = DemandTrackerAgent.cmd(agent, {BoostAction, %{amount: 100}})

      assert agent.state.demand == 100
    end

    test "cool action decreases demand and emits directive" do
      agent = DemandTrackerAgent.new()
      {agent, directives} = DemandTrackerAgent.cmd(agent, {CoolAction, %{amount: 10}})

      assert agent.state.demand == 40
      assert length(directives) == 1
      assert %Directive.Emit{signal: %Signal{type: "listing.demand.changed"}} = hd(directives)
    end

    test "cool action clamps demand at 0" do
      agent = DemandTrackerAgent.new()
      {agent, _} = DemandTrackerAgent.cmd(agent, {CoolAction, %{amount: 100}})

      assert agent.state.demand == 0
    end

    test "decay action decays demand toward 0" do
      agent = DemandTrackerAgent.new()
      {agent, _} = DemandTrackerAgent.cmd(agent, {BoostAction, %{amount: 30}})
      assert agent.state.demand == 80

      {agent, directives} =
        DemandTrackerAgent.cmd(agent, {DecayAction, %{auto: false, token: nil}})

      assert agent.state.demand == 78
      assert agent.state.ticks == 1
      assert Enum.any?(directives, &match?(%Directive.Emit{}, &1))
    end

    test "decay action from default 50 decays toward 0" do
      agent = DemandTrackerAgent.new()
      assert agent.state.demand == 50

      {agent, _} = DemandTrackerAgent.cmd(agent, {DecayAction, %{auto: false, token: nil}})

      assert agent.state.demand == 48
    end

    test "toggle auto decay enables and returns schedule directive" do
      agent = DemandTrackerAgent.new()
      assert agent.state.auto_decay_enabled == false

      {agent, directives} = DemandTrackerAgent.cmd(agent, ToggleAutoDecayAction)

      assert agent.state.auto_decay_enabled == true
      assert agent.state.tick_token != nil
      assert length(directives) == 1
      assert %Directive.Schedule{delay_ms: 10_000} = hd(directives)
    end

    test "toggle auto decay disables and clears token" do
      agent = DemandTrackerAgent.new()
      {agent, _} = DemandTrackerAgent.cmd(agent, ToggleAutoDecayAction)
      assert agent.state.auto_decay_enabled == true

      {agent, directives} = DemandTrackerAgent.cmd(agent, ToggleAutoDecayAction)

      assert agent.state.auto_decay_enabled == false
      assert agent.state.tick_token == nil
      assert directives == []
    end

    test "stale auto tick is ignored" do
      agent = DemandTrackerAgent.new()
      {agent, _} = DemandTrackerAgent.cmd(agent, ToggleAutoDecayAction)
      {agent, _} = DemandTrackerAgent.cmd(agent, {BoostAction, %{amount: 20}})
      assert agent.state.demand == 70

      stale_token = :erlang.unique_integer([:positive])

      {agent, directives} =
        DemandTrackerAgent.cmd(agent, {DecayAction, %{auto: true, token: stale_token}})

      assert agent.state.demand == 70
      assert directives == []
    end
  end

  describe "AgentServer with signals" do
    test "processes boost signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: DemandTrackerAgent,
          id: "test-demand-1",
          jido: JidoPhxStarter.Jido
        )

      signal = Signal.new!("listing.demand.boost", %{amount: 20}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.demand == 70
      GenServer.stop(pid)
    end

    test "processes cool signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: DemandTrackerAgent,
          id: "test-demand-2",
          jido: JidoPhxStarter.Jido
        )

      signal = Signal.new!("listing.demand.cool", %{amount: 15}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.demand == 35
      GenServer.stop(pid)
    end

    test "processes tick signal" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: DemandTrackerAgent,
          id: "test-demand-3",
          jido: JidoPhxStarter.Jido
        )

      boost_signal = Signal.new!("listing.demand.boost", %{amount: 30}, source: "/test")
      {:ok, _} = Jido.AgentServer.call(pid, boost_signal)

      tick_signal =
        Signal.new!("listing.demand.tick", %{auto: false, token: nil}, source: "/test")

      {:ok, agent} = Jido.AgentServer.call(pid, tick_signal)

      assert agent.state.demand == 78
      assert agent.state.ticks == 1
      GenServer.stop(pid)
    end

    test "auto decay toggle enables auto decay state" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: DemandTrackerAgent,
          id: "test-demand-4",
          jido: JidoPhxStarter.Jido
        )

      boost_signal = Signal.new!("listing.demand.boost", %{amount: 20}, source: "/test")
      {:ok, _} = Jido.AgentServer.call(pid, boost_signal)

      toggle_signal = Signal.new!("listing.demand.auto_decay.toggle", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, toggle_signal)

      assert agent.state.auto_decay_enabled == true
      assert agent.state.tick_token != nil

      GenServer.stop(pid)
    end
  end
end
