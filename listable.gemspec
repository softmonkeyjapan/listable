# frozen_string_literal: true

require_relative "lib/listable/version"

Gem::Specification.new do |spec|
  spec.name = "listable"
  spec.version = Listable::VERSION
  spec.authors = ["Loïc KARTONO"]
  spec.email = ["kartono.loic@gmail.com"]

  spec.summary = "Filtering and sorting engine for PostgreSQL-backed JSON API listings"
  spec.description = <<~DESCRIPTION
    Listable carries the query engine of a listing endpoint: the filter vocabulary, the sort
    vocabulary, the whitelist that guards both and the validation contract that turns a bad
    query string into a 422. It targets PostgreSQL, and it does not paginate.
  DESCRIPTION
  spec.homepage = "https://github.com/softmonkeyjapan/listable"
  spec.license = "MIT"

  # Ruby 3.4 is the floor because the gem is written against modern Active
  # Record only; Active Record 8.1 because the query building relies on its
  # type registry and its Arel surface.
  spec.required_ruby_version = ">= 3.4"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # The locale files are packaged alongside the code, and not because a
  # gem tidily ships its assets: the contract globs +config/locales+ at load
  # time to find the messages it resolves. A locale file left out of this
  # list is absent from the installed gem, the glob comes back short, and
  # every refusal the host serves its clients is a +translation missing+
  # string — with nothing in this repository turning red, because here the
  # files are on disk whether or not the package carries them.
  spec.files = Dir.glob("lib/**/*.rb") + Dir.glob("config/locales/*.yml") + ["LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "dry-validation", ">= 1.11"

  # Deliberately absent: any translation library, and any paginator. The
  # translated-attribute support is detected at runtime by asking the model
  # whether it answers the library's interface, so an application with no
  # translated attribute installs nothing extra; and applying a paginator to
  # the relation this gem returns is two lines in the host.
end
