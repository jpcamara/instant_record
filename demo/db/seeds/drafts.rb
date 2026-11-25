# Two drafts to open. yrby-forms builds each one's Yjs document from its title
# and text when it is saved.
module Drafts
  EXAMPLES = {
    "launch-plan" => ["Launch plan", "Ship the beta on Friday.\nTell the support team.\nWrite the release notes."],
    "meeting-agenda" => ["Meeting agenda", "Agenda:\n- Welcome"]
  }.freeze

  def self.apply
    EXAMPLES.each do |id, (title, text)|
      next if Draft.exists?(id: id)

      Draft.create!(id: id, title: title, body: text)
    end
  end
end
