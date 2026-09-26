# frozen_string_literal: true

require "test_helper"

class Ui::PaginationComponentTest < ViewComponent::TestCase
  test "renders nothing when everything fits on one page" do
    render_inline Ui::PaginationComponent.new(page: 1, pages: 1, path: "/services")
    assert_no_selector "nav"
  end

  test "first page has no previous link" do
    render_inline Ui::PaginationComponent.new(page: 1, pages: 3, path: "/services")
    assert_no_selector "a[rel=prev]"
    assert_selector "a[rel=next][href='/services?page=2']"
    assert_text "Page 1 of 3"
  end

  test "last page has no next link" do
    render_inline Ui::PaginationComponent.new(page: 3, pages: 3, path: "/services")
    assert_selector "a[rel=prev][href='/services?page=2']"
    assert_no_selector "a[rel=next]"
  end

  test "page one drops the page param instead of writing page=1" do
    render_inline Ui::PaginationComponent.new(page: 2, pages: 3, path: "/services")
    assert_selector "a[rel=prev][href='/services']"
  end

  test "carries the search and the filter through, never the old page" do
    render_inline Ui::PaginationComponent.new(page: 2, pages: 3, path: "/",
                                              params: { q: "markdown", category: "Data", page: "2", sort: nil })
    href = page.find("a[rel=next]")[:href]
    assert_includes href, "category=Data"
    assert_includes href, "q=markdown"
    assert_includes href, "page=3"
    assert_equal 1, href.scan("page=").size
    assert_not_includes href, "sort"
  end
end
