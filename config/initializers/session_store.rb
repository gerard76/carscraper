# The sort and the filters are kept in the session, and a cookie with no
# expiry on it dies with the browser -- which is exactly how "my filters are
# gone again every morning" comes about. Ninety days, so a laptop that is shut
# at night opens on the same six-seaters.
#
# Nothing is unlocked by holding this cookie: writing is behind http basic auth
# (ApplicationController#lock_the_writing), which the browser handles itself.
Rails.application.config.session_store :cookie_store,
                                       key: "_carscraper_session",
                                       expire_after: 90.days,
                                       same_site: :lax
