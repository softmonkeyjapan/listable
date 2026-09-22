# frozen_string_literal: true

require "active_record"
require "active_support/concern"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/object/blank"
require "dry/validation"

require_relative "listable/version"
require_relative "listable/casting"
require_relative "listable/field"
require_relative "listable/field_resolver"
require_relative "listable/filtering"

# Filtering and sorting engine for PostgreSQL-backed listing endpoints.
#
# +Listable+ is the only constant the gem defines at the root. Everything the
# gem owns is nested under it, because a gem that defined +Filterable+ or
# +Sortable+ would collide with the first +app/models/concerns/filterable.rb+
# of the application that installs it. For the same reason there is one module
# to include and not two: a model gets filtering and sorting together, and no
# host has to remember which half came from where.
module Listable
  extend ActiveSupport::Concern

  # The operator vocabulary, and no more than this.
  #
  # It is public because a host documents its own API from it. It is closed
  # because every entry is a decision about what a client may ask a listing to
  # do, and an operator that is not here is a condition the engine drops.
  OPERATORS = %w[= != > >= < <= in not_in like ilike is].freeze

  # Raised when a field that no whitelist carries reaches the query builder.
  #
  # From HTTP this never happens, the validation contract having answered 422
  # first. Reaching it means an internal caller named a field the model does
  # not declare, and raising turns a whitelist regression into a red test
  # rather than into an unfiltered listing served to a client who believes it
  # filtered.
  class UnknownField < StandardError; end

  class_methods do
    # Declares the fields a client may name, or reads back what was declared.
    #
    # ==== Parameters
    #
    # * +fields+ - the field names to declare, or +nil+ to read them back
    #
    # ==== Returns
    #
    # The declared field names, as a frozen array of strings.
    def listable_fields(fields = nil)
      return declared_listable_fields if fields.nil?

      @listable_fields = fields.map(&:to_s).freeze
    end

    # Narrows a relation by a list of conditions.
    #
    # It reads the current scope rather than the bare table, so that a listing
    # applies the gem on top of its own scoping and its authorization
    # narrowing rather than in place of them.
    #
    # ==== Parameters
    #
    # * +conditions+ - the positional list of conditions to apply
    # * +custom_filters+ - a map of field name to an object answering
    #   <tt>apply(relation, operator, value)</tt> and returning a relation
    #
    # ==== Returns
    #
    # The narrowed relation.
    def filtering(conditions, custom_filters = {})
      Filtering.new(all, conditions, custom_filters).apply
    end

    private

    # Reads the surface this class declared, or the one it inherits.
    #
    # The default is the empty list, and that is the single most important
    # property of the gem: a model that declares nothing exposes nothing,
    # refuses every filter and every sort, and discloses no column by omission.
    # Deriving the default from the model's columns or attributes would fail
    # open — the previous shape of this method did, and a secret column reached
    # a client with no test turning red.
    #
    # The lookup walks up to the superclass so that single-table inheritance
    # keeps the surface instead of silently losing it, and it tests the
    # instance variable with +defined?+ so that a subclass declaring the empty
    # list on purpose closes its own door rather than reopening its parent's.
    #
    # ==== Returns
    #
    # The declared field names, as a frozen array of strings.
    def declared_listable_fields
      return @listable_fields if defined?(@listable_fields)
      return superclass.listable_fields if superclass.respond_to?(:listable_fields)

      [].freeze
    end
  end
end

# The railtie exists only inside a Rails application. Rails is not a dependency
# of this gem — Active Record is — so the file is required behind the constant
# check rather than declared in the gemspec, and a host running Active Record
# without Rails loads the gem unchanged.
require_relative "listable/railtie" if defined?(Rails::Railtie)
