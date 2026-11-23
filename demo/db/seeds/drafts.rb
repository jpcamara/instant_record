# One draft to open, with its text already in a Yjs document.
module Drafts
  def self.apply
    return if Draft.exists?(id: "launch-plan")

    require "yrby"
    doc = Y::Doc.new
    doc.get_text("body").insert(0, "Ship it")
    Draft.create!(id: "launch-plan", title: "Launch plan", body: "Ship it",
      body_ydoc: Base64.strict_encode64(doc.encode_state_as_update))
  end
end
