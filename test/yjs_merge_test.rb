require "test_helper"
require "yrby"

class YjsMergeTest < Minitest::Test
  HLC = InstantRecord::HLC

  def setup
    reset_instant_record_tables!
    @t0 = Time.utc(2026, 11, 23, 12, 0, 0, 0)
    @model = syncable_model("Note") { sync_merge :body_ydoc, :yjs, text: :body }
    InstantRecord.sync(@model)
  end

  def teardown
    InstantRecord.sync
  end

  def test_concurrent_offline_edits_to_one_document_both_survive
    base = doc_with("Ship it")
    create_note(base)

    # Two clients edit from version 1 while offline.
    a = copy_of(base) { |text| text.insert(7, " today") }
    b = copy_of(base) { |text| text.insert(0, "Please ") }

    res_a = update_note("m-a", a, base_version: 1, at: @t0 + 10)
    res_b = update_note("m-b", b, base_version: 1, at: @t0 + 20)

    assert_equal "applied", res_a[:status]
    assert_equal "applied", res_b[:status]
    assert_equal "Please Ship it today", res_b[:server_attributes]["body"]

    record = @model.find("n-1")
    assert_equal "Please Ship it today", record.body
    assert_equal "Please Ship it today", text_of(record.body_ydoc)
  end

  def test_a_write_older_than_the_record_still_merges_its_edits
    base = doc_with("Notes")
    create_note(base)
    newer = copy_of(base) { |text| text.insert(5, " from Ada") }
    older = copy_of(base) { |text| text.insert(0, "Old ") }

    res_new = update_note("m-new", newer, at: @t0 + 20)
    result = update_note("m-old", older, at: @t0 + 21, hlc_at: @t0 + 5)

    assert_equal "applied", result[:status]
    assert_equal "Old Notes from Ada", @model.find("n-1").body
    assert_operator result[:hlc], :>, res_new[:hlc], "the merge is stamped after the write it merged into"
  end

  def test_create_fills_the_text_column_from_the_document
    create_note(doc_with("Hello"))

    assert_equal "Hello", @model.find("n-1").body
  end

  def test_the_text_column_comes_from_the_document_not_the_client
    base = doc_with("Real")
    create_note(base)

    update_note("m-text", nil, at: @t0 + 5, extra: { "body" => "Forged" })
    assert_equal "Real", @model.find("n-1").body

    edited = copy_of(base) { |text| text.insert(4, "ly") }
    update_note("m-both", edited, at: @t0 + 6, extra: { "body" => "Forged" })
    assert_equal "Really", @model.find("n-1").body
  end

  def test_a_state_that_is_not_a_yjs_update_is_rejected
    create_note(doc_with("Safe"))

    result = update_note("m-bad", "bm90IGEgeWpzIHVwZGF0ZQ==", at: @t0 + 5)

    assert_equal "rejected", result[:status]
    assert_match(/not a Yjs update/, result[:reason])
    assert_equal "Safe", @model.find("n-1").body
  end

  def test_two_yjs_columns_on_one_record_each_keep_every_edit
    @model = syncable_model("Note") do
      sync_merge :title_ydoc, :yjs, text: :title
      sync_merge :body_ydoc, :yjs, text: :body
    end
    InstantRecord.sync(@model)
    title = doc_with("Plan", name: "title")
    body = doc_with("Ship it")
    create_note(body, extra: { "title_ydoc" => title })

    # A edits both fields offline. B edits the title only.
    a_title = copy_of(title, name: "title") { |text| text.insert(4, " B") }
    a_body = copy_of(body) { |text| text.insert(7, " today") }
    b_title = copy_of(title, name: "title") { |text| text.insert(0, "Launch ") }

    update_note("m-a", a_body, at: @t0 + 10, extra: { "title_ydoc" => a_title })
    update_note("m-b", nil, at: @t0 + 20, extra: { "title_ydoc" => b_title })

    record = @model.find("n-1")
    assert_equal "Launch Plan B", record.title
    assert_equal "Ship it today", record.body
  end

  def test_maps_arrays_and_xml_in_one_document_all_merge
    base = Base64.strict_encode64(Y::Doc.new.tap { |doc| doc.get_map("fields").set("status", "draft") }.encode_state_as_update)
    create_note(base)

    a = edit(base) do |doc|
      doc.get_map("fields").set("owner", "Ada")
      doc.get_array("tags").push("urgent")
      doc.get_xml_text("notes").insert(0, "Call support")
    end
    b = edit(base) do |doc|
      doc.get_map("fields").set("due", "Friday")
      doc.get_array("tags").push("docs")
      doc.get_xml_text("notes").set_attribute("lang", "en")
    end

    update_note("m-a", a, at: @t0 + 10)
    update_note("m-b", b, at: @t0 + 20)

    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(@model.find("n-1").body_ydoc))
    assert_equal({ "status" => "draft", "owner" => "Ada", "due" => "Friday" }, doc.get_map("fields").to_h)
    assert_equal %w[docs urgent], doc.get_array("tags").to_a.sort
    assert_equal "Call support", doc.get_xml_text("notes").to_s
    assert_equal "en", doc.get_xml_text("notes").attributes["lang"]
  end

  def test_a_plain_column_beside_a_yjs_column_keeps_its_own_policy
    base = doc_with("Ship it")
    create_note(base)

    a = copy_of(base) { |text| text.insert(7, " today") }
    b = copy_of(base) { |text| text.insert(0, "Please ") }
    update_note("m-a", a, at: @t0 + 10, extra: { "state" => "review" })
    update_note("m-b", b, at: @t0 + 20, extra: { "state" => "done" })

    record = @model.find("n-1")
    assert_equal "Please Ship it today", record.body
    assert_equal "done", record.state, "the plain column is last-write-wins"
  end

  def test_text_is_only_for_yjs_columns
    error = assert_raises(ArgumentError) { syncable_model("Bad") { sync_merge :title, :lww, text: :body } }
    assert_match(/only to :yjs/, error.message)
  end

  private

  def create_note(state, extra: {})
    HLC.with_clock(-> { @t0 }) do
      on_server do
        InstantRecord::MutationApplier.apply({
          id: "m-create", record_type: "Note", record_id: "n-1", operation: "create",
          hlc: HLC.from_time(@t0, node: "clientcc"),
          changes: { "body_ydoc" => state, "updated_at" => @t0.iso8601(6) }.merge(extra)
        })
      end
    end
  end

  def update_note(id, state, at:, base_version: nil, hlc_at: at, extra: {})
    changes = { "updated_at" => hlc_at.iso8601(6) }.merge(extra)
    changes["body_ydoc"] = state if state
    mutation = {
      id: id, record_type: "Note", record_id: "n-1", operation: "update",
      hlc: HLC.from_time(hlc_at, node: "client#{id.delete("^a-z")[0, 3]}"), changes: changes
    }
    mutation[:base_version] = base_version if base_version
    HLC.with_clock(-> { at }) { on_server { InstantRecord::MutationApplier.apply(mutation) } }
  end

  def doc_with(string, name: "body")
    doc = Y::Doc.new
    doc.get_text(name).insert(0, string)
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  # A new client's copy of `state`, with the block editing its Y.Text `name`.
  def copy_of(state, name: "body")
    edit(state) { |doc| yield doc.get_text(name) }
  end

  # A new client's copy of `state`, edited by the block.
  def edit(state)
    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(state))
    yield doc
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  def text_of(state)
    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(state))
    doc.read_text("body").to_s
  end
end
