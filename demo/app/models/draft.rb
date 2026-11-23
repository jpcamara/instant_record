# A text two people can edit offline at once. The page keeps the text as a Yjs
# document and saves its whole state in `body_ydoc`. The server merges each
# save into what it holds, so edits made apart both survive, and fills `body`
# from the result.
class Draft < ApplicationRecord
  include InstantRecord::Syncable

  sync_merge :body_ydoc, :yjs, text: :body

  validates :title, presence: true, length: { maximum: 120 }
end
