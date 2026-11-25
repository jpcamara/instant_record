# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "yjs", to: "yjs.js" # Yjs 13.6.27, bundled into one module
pin "yrby-forms/column", to: "yrby-forms.js" # the yrby-forms gem's column.js asset
