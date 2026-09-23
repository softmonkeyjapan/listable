# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The suite runs against a real PostgreSQL database — there is no example
# application and no in-memory substitute — so the adapter is a development
# dependency here rather than a runtime dependency of the gem, which lets a
# host bring its own.
# Active Record 8.1 calls +JSON.parse+ with a positional options hash, a
# signature the json gem dropped in its 3.0 line. Left unpinned, every read of
# the harness's JSON document column — the storage of the translated attribute
# the engine resolves — raises before a single assertion runs.
gem "json", "~> 2.7"
gem "pg", "~> 1.5"

# The README's query-string examples are executed by the suite rather than
# retyped into it, so the examples have to be parsed the way a web server would
# parse them. Rack owns that parsing; it is a development dependency and never
# a runtime one, because the gem itself never sees a request.
gem "rack", "~> 3.1"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.66"
gem "rubocop-performance", "~> 1.21"
gem "rubocop-rspec", "~> 3.0"

# Mobility is the translation library the gem resolves translated attributes
# against, and it is a development dependency on purpose: the gemspec declares
# it nowhere, and the engine detects it at runtime by asking the model whether
# it answers the library's interface.
#
# It sits in a group of its own so that the suite can be run in both worlds
# without editing anything — <tt>BUNDLE_WITHOUT=translations bundle exec
# rspec</tt> leaves the library off the load path entirely, which makes "the
# dependency is optional" a measurement rather than an assertion.
group :translations do
  gem "mobility", "~> 1.3"
end
