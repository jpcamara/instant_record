# A title and a text two people can edit offline at once. The page keeps each
# field as a Yjs document and saves their whole states in `title_ydoc` and
# `body_ydoc`. The server merges each save into what it holds, so edits made
# apart all survive, and fills `title` and `body` from the result.
class Draft < ApplicationRecord
  include InstantRecord::Syncable

  sync_merge :title_ydoc, :yjs, text: :title
  sync_merge :body_ydoc, :yjs, text: :body

  validates :title, presence: true, length: { maximum: 120 }
end
