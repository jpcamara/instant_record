# Two drafts to open, each with its text already in a Yjs document.
module Drafts
  EXAMPLES = {
    "launch-plan" => ["Launch plan", "Ship the beta on Friday.\nTell the support team.\nWrite the release notes."],
    "meeting-agenda" => ["Meeting agenda", "Agenda:\n- Welcome"]
  }.freeze

  def self.apply
    require "yrby"

    EXAMPLES.each do |id, (title, text)|
      next if Draft.exists?(id: id)

      doc = Y::Doc.new
      doc.get_text("body").insert(0, text)
      Draft.create!(id: id, title: title, body: text,
        body_ydoc: Base64.strict_encode64(doc.encode_state_as_update))
    end
  end
end
