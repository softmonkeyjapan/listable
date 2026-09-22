# frozen_string_literal: true

require "active_record"
require "dry/validation"

require_relative "listable/version"

# Filtering and sorting engine for PostgreSQL-backed listing endpoints.
#
# +Listable+ is the only constant the gem defines at the root. Everything the
# gem owns is nested under it, because a gem that defined +Filterable+ or
# +Sortable+ would collide with the first +app/models/concerns/filterable.rb+
# of the application that installs it.
module Listable
end

# The railtie exists only inside a Rails application. Rails is not a dependency
# of this gem — Active Record is — so the file is required behind the constant
# check rather than declared in the gemspec, and a host running Active Record
# without Rails loads the gem unchanged.
require_relative "listable/railtie" if defined?(Rails::Railtie)
