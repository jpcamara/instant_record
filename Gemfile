source "https://rubygems.org"

gemspec

group :development, :test do
  gem "sqlite3"
  gem "minitest"
  gem "rake"
  # Serves the app the browser test of the file store runs against (test/browser).
  gem "puma"
  # yrby merges sync_merge :yjs columns, and yrby-forms fills the columns
  # named by fields: (test/yjs_merge_test.rb). yrby-forms is not released yet.
  # Its repository holds yrby too, so both come from the branch, and
  # installing them builds yrby's Rust extension.
  git "https://github.com/jpcamara/yrby.git", branch: "feat/yrby-forms" do
    gem "yrby"
    gem "yrby-forms"
  end
end
