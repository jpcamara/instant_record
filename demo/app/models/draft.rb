# A title and a text two people can edit offline at once. The form keeps both
# in one Yjs document and saves its whole state in `fields_ydoc`. The server
# merges each save into the document it holds, so edits made apart all
# survive, and yrby-forms fills `title` and `body` from the result.
class Draft < ApplicationRecord
  include InstantRecord::Syncable

  sync_merge :fields_ydoc, :yjs

  server_only do
    has_collaborative_fields :title, :body, column: :fields_ydoc
  end

  validates :title, presence: true, length: { maximum: 120 }
end
