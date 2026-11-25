# The Drafts demo. `fields_ydoc` holds a Yjs document as a Base64 update, and
# the server merges each write into it (sync_merge :yjs). `title` and `body`
# are the plain text yrby-forms reads out of it.
class CreateDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :drafts, id: :string do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.text :fields_ydoc
      t.integer :server_version, default: 0, null: false
      t.string :sync_state, default: "synced", null: false
      t.timestamps
    end
  end
end
