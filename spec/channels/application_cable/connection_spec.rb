require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "connects a signed-in user" do
    user = create(:user)
    session = user.sessions.create!
    cookies.signed[:session_id] = session.id
    connect "/cable"
    expect(connection.current_user).to eq(user)
  end

  it "rejects anyone else" do
    expect { connect "/cable" }.to have_rejected_connection
  end
end
