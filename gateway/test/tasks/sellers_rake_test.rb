# frozen_string_literal: true

require "test_helper"
require "rake"

class SellersRakeTest < ActiveSupport::TestCase
  include MailHelpers

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["sellers:invite_approved"].reenable
  end

  test "invites approved early-access sellers who have no account yet" do
    approved = build_inquiry
    approved.update!(status: "approved")
    build_inquiry(email: "pending@example.com")
    signed_up = build_inquiry(email: "done@example.com")
    signed_up.update!(status: "approved")
    Seller.create!(email: "done@example.com")

    assert_output(/Invited 1 approved seller\./) { Rake::Task["sellers:invite_approved"].invoke }
    assert_equal [ [ "seller@example.com" ] ], ActionMailer::Base.deliveries.map(&:to)
  end
end
