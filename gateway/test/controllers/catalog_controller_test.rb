require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index lists the catalog" do
    get root_url
    assert_response :success
    assert_select "h1", text: "Services your agent can pay for."
    assert_select "a[href='/s/scrape-markdown']"
  end

  test "index filters by category" do
    get root_url(category: "Messaging")
    assert_response :success
    assert_select "a[href='/s/send-whatsapp']"
    assert_select "a[href='/s/scrape-markdown']", count: 0
  end

  test "show renders a service" do
    get service_url("scrape-markdown")
    assert_response :success
    assert_select "h1", text: "Scrape URL to Markdown"
    assert_select "pre", minimum: 1
  end

  test "theme cookie drives data-theme" do
    cookies[:theme] = "bottrunk-dark"
    get root_url
    assert_select "html[data-theme=bottrunk-dark]"
  end
end
