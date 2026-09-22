# frozen_string_literal: true

module Listable
  # The released version of the gem.
  #
  # It lives in its own file so that the gemspec can read it with a bare
  # +require_relative+, without loading +lib/listable.rb+ and, through it,
  # Active Record: a gemspec must be evaluable before +bundle install+ has
  # resolved a single dependency.
  VERSION = "0.1.0"
end
