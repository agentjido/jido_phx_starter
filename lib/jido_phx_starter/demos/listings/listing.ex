defmodule JidoPhxStarter.Demos.ListingsDomain.Listing do
  @moduledoc """
  Marketplace Listing resource with AshJido extension.

  Demonstrates Ash resources as Jido agent tools:
  - CRUD operations exposed via `jido do ... end` DSL
  - Policy enforcement (guest cannot create, owner-only updates)
  - ETS data layer (resets on restart, perfect for demos)

  Generated modules:
  - `Listing.Jido.Create` - create_listing
  - `Listing.Jido.Read` - list_listings
  - `Listing.Jido.UpdatePrice` - update_listing_price
  - `Listing.Jido.UpdateQuantity` - update_listing_quantity
  - `Listing.Jido.Publish` - publish_listing
  - `Listing.Jido.Destroy` - delete_listing
  """
  use Ash.Resource,
    domain: JidoPhxStarter.Demos.ListingsDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJido],
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? false
  end

  jido do
    action :create,
      name: "create_listing",
      description: "Create a new marketplace listing",
      tags: ["marketplace"]

    action :read,
      name: "list_listings",
      description: "List all marketplace listings",
      tags: ["marketplace"]

    action :update_price,
      name: "update_listing_price",
      description: "Update the price of a listing",
      tags: ["marketplace"]

    action :update_quantity,
      name: "update_listing_quantity",
      description: "Update the quantity of a listing",
      tags: ["marketplace"]

    action :publish,
      name: "publish_listing",
      description: "Publish a draft listing",
      tags: ["marketplace", "authz"]

    action :destroy,
      name: "delete_listing",
      description: "Delete a listing",
      tags: ["marketplace", "destructive"]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :price, :quantity]

      change fn changeset, %{actor: actor} ->
        seller_id =
          case actor do
            %{id: id} when is_binary(id) -> id
            %{"id" => id} when is_binary(id) -> id
            _ -> nil
          end

        Ash.Changeset.force_change_attribute(changeset, :seller_id, seller_id)
      end

      change set_attribute(:status, :draft)
    end

    update :update_price do
      accept [:price]
    end

    update :update_quantity do
      accept [:quantity]
    end

    update :publish do
      accept []
      change set_attribute(:status, :published)
    end

    destroy :destroy
  end

  policies do
    # Guests can only see published listings
    # Users/admins can see all listings
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(status == :published)
    end

    # Must be logged in (user/admin) to create
    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :user)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # User can update their own listings, admin can update any
    policy action_type(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(^actor(:role) == :user and seller_id == ^actor(:id))
    end

    # User can delete their own listings, admin can delete any
    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(^actor(:role) == :user and seller_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :price, :decimal, allow_nil?: false, public?: true
    attribute :quantity, :integer, default: 0, public?: true

    attribute :status, :atom,
      default: :draft,
      constraints: [one_of: [:draft, :published, :sold_out]],
      public?: true

    attribute :seller_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end
end
