# frozen_string_literal: true

require "test_helper"

module Mcp
  class ToolsTest < ActiveSupport::TestCase
    test "a tool that raises answers isError and reports the exception" do
      OrderLookup.singleton_class.alias_method(:find_without_boom, :find)
      OrderLookup.define_singleton_method(:find) { |*| raise ActiveRecord::ConnectionNotEstablished, "database is gone" }
      result = nil
      begin
        report = assert_error_reported(ActiveRecord::ConnectionNotEstablished) do
          result = Tools.call("bottrunk_order_status", { "order_id" => "8kPz3n" })
        end
      ensure
        OrderLookup.singleton_class.alias_method(:find, :find_without_boom)
        OrderLookup.singleton_class.remove_method(:find_without_boom)
      end

      assert result[:isError]
      assert_match "database is gone", result[:content][0][:text]
      assert report.handled?
      assert_equal "bottrunk_order_status", report.context[:tool]
    end

    test "a tool that refuses bad input is not an error worth reporting" do
      assert_no_error_reported do
        assert Tools.call("bottrunk_order_status", { "order_id" => "" })[:isError]
      end
    end
  end
end
