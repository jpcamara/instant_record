require "test_helper"
require "yrby"

class DraftsControllerTest < ActionDispatch::IntegrationTest
  test "index lists drafts, and create opens the new draft" do
    get drafts_url

    assert_response :success
    assert_select "form.draft-form"

    post drafts_url, params: { draft: { title: "Notes" } }

    draft = Draft.find_by!(title: "Notes")
    assert_redirected_to draft_url(draft)
  end

  test "show renders the editor, and with ?fragment=1 only the stored state" do
    state = state_with("Hello")
    draft = Draft.create!(id: "d-1", title: "Plan", body: "Hello", body_ydoc: state)

    get draft_url(draft)

    assert_response :success
    assert_select "div.page[data-controller=draft][data-instant-refresh]"
    assert_select "input.draft-title[value=Plan]"
    assert_select "textarea.draft-editor", text: "Hello"

    get draft_url(draft, fragment: 1)

    assert_select "textarea", count: 0
    assert_select "[data-body-state=?]", state
  end

  test "update stores the document and answers with the stored state" do
    draft = Draft.create!(id: "d-1", title: "Plan")
    title = state_with("Plan B", name: "title")
    body = state_with("Hello")

    patch draft_url(draft), params: { draft: { title: "Plan B", title_ydoc: title, body: "Hello", body_ydoc: body } }

    assert_response :success
    assert_select "[data-title-state=?][data-body-state=?]", title, body
    assert_equal ["Plan B", "Hello"], draft.reload.values_at(:title, :body)
  end

  test "two offline edits to one draft both survive the sync" do
    base = state_with("Ship it")
    Draft.create!(id: "d-1", title: "Plan", body: "Ship it", body_ydoc: base)

    sync("m-a", edit(base) { |text| text.insert(7, " today") })
    sync("m-b", edit(base) { |text| text.insert(0, "Please ") })

    assert_equal "Please Ship it today", Draft.find("d-1").body
  end

  test "offline edits to the title and the text all survive the sync" do
    title = state_with("Plan", name: "title")
    body = state_with("Ship it")
    Draft.create!(id: "d-1", title: "Plan", title_ydoc: title, body: "Ship it", body_ydoc: body)

    sync("m-a", edit(body) { |text| text.insert(7, " today") },
      title_ydoc: edit(title, name: "title") { |text| text.insert(4, " B") })
    sync("m-b", nil, title_ydoc: edit(title, name: "title") { |text| text.insert(0, "Launch ") })

    assert_equal ["Launch Plan B", "Ship it today"], Draft.find("d-1").values_at(:title, :body)
  end

  private

  def sync(id, body_ydoc, **changes)
    changes[:body_ydoc] = body_ydoc if body_ydoc
    post "/instant_record/mutations", as: :json, params: { mutations: [
      { id: id, record_type: "Draft", record_id: "d-1", operation: "update", base_version: 0,
        changes: changes }
    ] }
    assert_equal "applied", response.parsed_body.dig("results", 0, "status")
  end

  def state_with(string, name: "body")
    doc = Y::Doc.new
    doc.get_text(name).insert(0, string)
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  # Another browser's copy of `state`, with the block editing its Y.Text `name`.
  def edit(state, name: "body")
    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(state))
    yield doc.get_text(name)
    Base64.strict_encode64(doc.encode_state_as_update)
  end
end
