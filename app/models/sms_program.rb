# The text-alert program as registered with the carriers (A2P 10DLC, Sole
# Proprietor). One place for the wording the public pages, the consent
# checkbox, and the HELP reply all use, so they always match the registration.
module SmsProgram
  NAME = "Auto Pool Temp alerts".freeze
  SENDER = "Mitch VanDuyn".freeze
  CONTACT_EMAIL = "mitch@catprint.com".freeze
  FREQUENCY = "up to 3 messages a day, only when your pool heater, pump, or cover should change".freeze

  CONSENT = "I agree to receive #{NAME} from #{SENDER} by text message at this number: pool heater, pump, and " \
            "cover advice, #{FREQUENCY}. Message and data rates may apply. Reply STOP to opt out, HELP for help. " \
            "Consent isn't a condition of any purchase.".freeze

  HELP = "#{NAME} (#{SENDER}): pool heater advice, #{FREQUENCY}. Msg & data rates may apply. " \
         "Reply STOP to opt out. Help: #{CONTACT_EMAIL}".freeze
end
