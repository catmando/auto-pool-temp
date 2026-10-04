require "rails_helper"

RSpec.describe "Text message log" do
  let(:pool) { create(:pool) }

  before { sign_in_as(pool.user) }

  it "lists the pool's texts" do
    create(:text_message, pool: pool, body: "Set to 90")
    create(:text_message, pool: pool, direction: "inbound", from: "+15125550100", body: "88")
    create(:text_message, pool: create(:pool), body: "Someone else's")
    get text_messages_path
    expect(response.body).to include("Set to 90", "From +15125550100")
    expect(response.body).not_to include("Someone else")
  end

  it "handles an empty log" do
    get text_messages_path
    expect(response.body).to include("No messages yet")
  end
end
