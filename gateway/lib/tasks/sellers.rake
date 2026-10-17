# frozen_string_literal: true

namespace :sellers do
  desc "Email approved early-access sellers who have no account yet that accounts are open. Run once."
  task invite_approved: :environment do
    sent = 0
    SellerInquiry.where(status: "approved").find_each do |inquiry|
      next if Seller.exists?(email: inquiry.email)

      Notifications::Deliver.now(SellerMailer.with(inquiry: inquiry).invitation)
      sent += 1
    end
    puts "Invited #{sent} approved seller#{'s' unless sent == 1}."
  end
end
