require "test_helper"
require "yrby"

class DraftsControllerTest < ActionDispatch::IntegrationTest
  test "index lists drafts, and create opens the new draft" do
    get drafts_url

    assert_response :success
    assert_select "form.draft-form collaborative-fields[name=?]", "draft[fields_ydoc]"

    post drafts_url, params: { draft: { title: "Notes" } }

    draft = Draft.find_by!(title: "Notes")
    assert_redirected_to draft_url(draft)
    assert_equal "Notes", text_of(draft.fields_ydoc, "title")
  end

  test "show renders the form around the draft's document" do
    draft = Draft.create!(id: "d-1", title: "Plan", body: "Hello")

    get draft_url(draft)

    assert_response :success
    assert_select "collaborative-fields[autosave][name=?][value=?]", "draft[fields_ydoc]", draft.fields_ydoc
    assert_select "collaborative-field[name=title] input.draft-title[value=Plan]"
    assert_select "collaborative-field[name=body] textarea.draft-editor", text: "Hello"
  end

  test "update merges the posted document and fills the fields from it" do
    draft = Draft.create!(id: "d-1", title: "Plan", body: "Ship it")
    posted = edit(draft.fields_ydoc) { |doc| doc.get_text("fields/title").insert(4, " B") }
    draft.update!(fields_ydoc: edit(draft.fields_ydoc) { |doc| doc.get_text("fields/body").insert(7, " today") })

    patch draft_url(draft), params: { draft: { title: "Plan B", body: "Ship it", fields_ydoc: posted } }

    assert_redirected_to draft_url(draft)
    assert_equal ["Plan B", "Ship it today"], draft.reload.values_at(:title, :body)
  end

  test "update refuses a save that leaves the draft invalid" do
    draft = Draft.create!(id: "d-1", title: "Plan", body: "Ship it")

    patch draft_url(draft), params: { draft: { title: "", body: "Ship it today" } }

    assert_response :unprocessable_entity
    assert_equal ["Plan", "Ship it"], draft.reload.values_at(:title, :body)
  end

  test "two offline edits to one draft both survive the sync" do
    base = Draft.create!(id: "d-1", title: "Plan", body: "Ship it").fields_ydoc

    sync("m-a", edit(base) { |doc| doc.get_text("fields/body").insert(7, " today") })
    sync("m-b", edit(base) { |doc| doc.get_text("fields/body").insert(0, "Please ") })

    assert_equal "Please Ship it today", Draft.find("d-1").body
  end

  test "offline edits to the title and the text all survive the sync" do
    base = Draft.create!(id: "d-1", title: "Plan", body: "Ship it").fields_ydoc

    sync("m-a", edit(base) do |doc|
      doc.get_text("fields/title").insert(4, " B")
      doc.get_text("fields/body").insert(7, " today")
    end)
    sync("m-b", edit(base) { |doc| doc.get_text("fields/title").insert(0, "Launch ") })

    assert_equal ["Launch Plan B", "Ship it today"], Draft.find("d-1").values_at(:title, :body)
  end

  private

  # A browser's synced write. It sends the document and the title it had on
  # screen, and the server reads the title from the merged document.
  def sync(id, fields_ydoc)
    post "/instant_record/mutations", as: :json, params: { mutations: [
      { id: id, record_type: "Draft", record_id: "d-1", operation: "update", base_version: 0,
        changes: { fields_ydoc: fields_ydoc, title: text_of(fields_ydoc, "title") } }
    ] }
    assert_equal "applied", response.parsed_body.dig("results", 0, "status")
  end

  def text_of(state, field)
    load_doc(state).read_text("fields/#{field}")
  end

  # Another browser's copy of `state`, with the block editing it.
  def edit(state)
    doc = load_doc(state)
    yield doc
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  def load_doc(state)
    Y::Doc.new.tap { |doc| doc.apply_update(Base64.strict_decode64(state)) }
  end
end
