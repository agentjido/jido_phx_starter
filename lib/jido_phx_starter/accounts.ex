defmodule JidoPhxStarter.Accounts do
  use Ash.Domain,
    otp_app: :jido_phx_starter

  resources do
    resource JidoPhxStarter.Accounts.Token
    resource JidoPhxStarter.Accounts.User
  end
end
