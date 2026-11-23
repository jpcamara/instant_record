require "base64"

module InstantRecord
  # Server-side merging for `sync_merge :col, :yjs` columns. Such a column holds
  # a Yjs document's state as a Base64 update. Merging two states keeps every
  # edit either one has, in any order, so the server merges each write into
  # what it stores instead of choosing between them.
  #
  # yrby is required on first use, so only an app with a :yjs column needs it.
  module YjsMerge
    # An update that doesn't decode. The mutation is rejected.
    Invalid = Class.new(StandardError)

    module_function

    # The merged state of every given Base64 state, Base64-encoded, and the
    # merged document.
    def merge(*states)
      doc = new_doc
      states.each do |state|
        next if state.nil? || state.to_s.empty?

        begin
          doc.apply_update(Base64.strict_decode64(state.to_s))
        rescue ArgumentError, ::Y::Error => e
          raise Invalid, "not a Yjs update: #{e.message}"
        end
      end
      [Base64.strict_encode64(doc.encode_state_as_update), doc]
    end

    # The document's Y.Text called `name`, as a plain String.
    def text(doc, name)
      doc.read_text(name).to_s
    end

    def new_doc
      require "yrby"
      ::Y::Doc.new
    rescue LoadError
      raise LoadError, "sync_merge :yjs needs the yrby gem on the server. Add `gem \"yrby\"` to the Gemfile."
    end
  end
end
