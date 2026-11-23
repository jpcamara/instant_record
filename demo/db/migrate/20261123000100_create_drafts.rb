# The Drafts demo. `body_ydoc` holds the text's Yjs document as a Base64
# update, and the server merges each write into it (sync_merge :yjs). `body`
# is the plain text the server reads out of that document.
class CreateDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :drafts, id: :string do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.text :body_ydoc
      t.integer :server_version, default: 0, null: false
      t.string :sync_state, default: "synced", null: false
      t.timestamps
    end
  end
end
