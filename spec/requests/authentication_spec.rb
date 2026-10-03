require "rails_helper"

RSpec.describe "Authentication" do
  describe "registration" do
    it "is the landing page when no account exists" do
      get new_session_path
      expect(response).to redirect_to(new_registration_path)
    end

    it "creates the first account, signs in, and goes to settings" do
      expect {
        post registration_path, params: { user: { email_address: "me@example.com", password: "password123",
                                                   password_confirmation: "password123" } }
      }.to change(User, :count).by(1)
      expect(response).to redirect_to(edit_pool_path)
      follow_redirect!
      expect(response.body).to include("Settings")
    end

    it "re-renders with errors" do
      post registration_path, params: { user: { email_address: "me@example.com", password: "short",
                                                 password_confirmation: "short" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("too short")
    end

    it "is closed once an account exists" do
      create(:user)
      get new_registration_path
      expect(response).to redirect_to(new_session_path)
      post registration_path, params: { user: { email_address: "x@example.com", password: "password123" } }
      expect(User.count).to eq(1)
    end
  end

  describe "sessions" do
    let!(:user) { create(:user) }

    it "requires sign in" do
      get root_path
      expect(response).to redirect_to(new_session_path)
    end

    it "shows the sign in form" do
      get new_session_path
      expect(response.body).to include("Sign in")
    end

    it "signs in with valid credentials" do
      sign_in_as(user)
      expect(response).to redirect_to(root_url)
    end

    it "rejects bad credentials" do
      post session_path, params: { email_address: user.email_address, password: "wrong" }
      expect(response).to redirect_to(new_session_path)
    end

    it "signs out" do
      sign_in_as(user)
      delete session_path
      expect(response).to redirect_to(new_session_path)
      get root_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
