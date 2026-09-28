defmodule JidoPhxStarterWeb.Demos.ChatRequestTest do
  use ExUnit.Case, async: true

  alias JidoPhxStarterWeb.Demos.ChatLive
  alias JidoPhxStarterWeb.Demos.ListingManagerLive

  for live_module <- [ChatLive, ListingManagerLive] do
    test "#{inspect(live_module)} accepts the agent request handle" do
      socket =
        Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, %{
          input: "  hello  ",
          running?: false,
          agent_pid: self(),
          messages: []
        })

      assert {:noreply, socket} = unquote(live_module).handle_event("send", %{}, socket)
      assert socket.assigns.running?
      assert socket.assigns.input == ""

      assert [%{role: :user, content: "hello"}, %{role: :assistant, pending: true}] =
               socket.assigns.messages

      assert_receive {:"$gen_cast", {:signal, %Jido.Signal{data: %{query: "hello"}}}}
    end
  end
end
