# Public pages (no sign-in): what the text alerts are, and the privacy policy.
# Carriers' reviewers read these when approving the SMS registration.
class PagesController < ApplicationController
  allow_unauthenticated_access

  def sms; end
  def privacy; end
end
