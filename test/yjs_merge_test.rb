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

  def test_text_is_only_for_yjs_columns
    error = assert_raises(ArgumentError) { syncable_model("Bad") { sync_merge :title, :lww, text: :body } }
    assert_match(/only to :yjs/, error.message)
  end

  private

  def create_note(state)
    HLC.with_clock(-> { @t0 }) do
      on_server do
        InstantRecord::MutationApplier.apply({
          id: "m-create", record_type: "Note", record_id: "n-1", operation: "create",
          hlc: HLC.from_time(@t0, node: "clientcc"),
          changes: { "body_ydoc" => state, "updated_at" => @t0.iso8601(6) }
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

  def doc_with(string)
    doc = Y::Doc.new
    doc.get_text("body").insert(0, string)
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  # A new client's copy of `state`, edited by the block.
  def copy_of(state)
    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(state))
    yield doc.get_text("body")
    Base64.strict_encode64(doc.encode_state_as_update)
  end

  def text_of(state)
    doc = Y::Doc.new
    doc.apply_update(Base64.strict_decode64(state))
    doc.read_text("body").to_s
  end
end
