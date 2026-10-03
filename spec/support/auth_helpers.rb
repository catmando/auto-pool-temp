module AuthHelpers
  def sign_in_as(user, password: "password123")
    if respond_to?(:visit)
      visit new_session_path
      fill_in "Email", with: user.email_address
      fill_in "Password", with: password
      click_button "Sign in"
    else
      post session_path, params: { email_address: user.email_address, password: password }
    end
  end
end
