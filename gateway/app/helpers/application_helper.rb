module ApplicationHelper
  # "Algorand, Base or Solana": the networks the 402 offers right now, so a
  # page never claims a network we do not take (Payments::Networks.offered).
  def networks_phrase = Payments::BuildRequirements.network_names.to_sentence(last_word_connector: " or ", two_words_connector: " or ")
end
