# The Drafts demo. `title_ydoc` and `body_ydoc` each hold a Yjs document as a
# Base64 update, and the server merges each write into them (sync_merge :yjs).
# `title` and `body` are the plain text the server reads out of them.
class CreateDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :drafts, id: :string do |t|
      t.string :title, null: false
      t.text :title_ydoc
      t.text :body, null: false, default: ""
      t.text :body_ydoc
      t.integer :server_version, default: 0, null: false
      t.string :sync_state, default: "synced", null: false
      t.timestamps
    end
  end
end
