# Two drafts to open, each with its title and text already in Yjs documents.
module Drafts
  EXAMPLES = {
    "launch-plan" => ["Launch plan", "Ship the beta on Friday.\nTell the support team.\nWrite the release notes."],
    "meeting-agenda" => ["Meeting agenda", "Agenda:\n- Welcome"]
  }.freeze

  def self.apply
    require "yrby"

    EXAMPLES.each do |id, (title, text)|
      next if Draft.exists?(id: id)

      Draft.create!(id: id, title: title, title_ydoc: state("title", title),
        body: text, body_ydoc: state("body", text))
    end
  end

  # A Yjs document holding `string` as its Y.Text `name`, Base64-encoded.
  def self.state(name, string)
    doc = Y::Doc.new
    doc.get_text(name).insert(0, string)
    Base64.strict_encode64(doc.encode_state_as_update)
  end
end
