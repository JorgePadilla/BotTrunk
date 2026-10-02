# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
#
# The same list scrubs what goes to Honeybadger (config/initializers/honeybadger.rb),
# where request headers are keys too: `payment` and `signature` catch the signed
# transaction in PAYMENT-SIGNATURE / X-PAYMENT, `account` the bank details of a
# lempira deposit.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # An authorization PIN is 4 digits that can move money; never log it in plain text.
  :pin,
  :payment, :signature, :account
]
