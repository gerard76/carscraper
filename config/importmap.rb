# Pin npm packages by running ./bin/importmap


# pin "Chart.bundle", to: "Chart.bundle.js"
pin "chartkick", to: "chartkick.js"

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
