# frozen_string_literal: true

module Listable
  # One listing, declared once: the model whose surface it serves, the custom
  # filters and the custom sorts it adds to that surface, and the order it
  # answers when a request names none.
  #
  # Without it, a listing serving a custom filter names that filter three
  # times — to the contract's filterable surface, to the contract's custom
  # filters, and to +filtering+ — and a listing two endpoints share names it
  # three times per endpoint. Each copy is a chance for one of them to drift:
  # a field the contract accepts and +filtering+ does not serve narrows on
  # nothing and raises, and a filter +filtering+ serves and the contract does
  # not ask refuses nothing. Here the surfaces are derived from the one map
  # that +filtering+ and +sorting+ are handed.
  #
  # Pagination stays out, as it does everywhere in this gem.
  class Definition
    # Builds the definition of one listing.
    #
    # ==== Parameters
    #
    # * +model+ - the model the listing reads, including Listable
    # * +filters+ - the custom filters of the listing, by the field they serve
    # * +sorts+ - the custom sorts of the listing, by the key they serve
    # * +default_sort+ - the sort parameter a request naming none is ordered
    #   by, in the request's own format; +nil+ leaves the gem's default order
    #
    # The default sort is not checked against the surface here: the model's
    # surface is read lazily, for the reason #contract gives, so a default
    # naming an undeclared key raises in the engine the first time a request
    # leaves the order out — which any spec of that listing does.
    #
    # ==== Returns
    #
    # A definition.
    def initialize(model, filters: {}, sorts: {}, default_sort: nil)
      @model = model
      @custom_filters = filters.to_h.transform_keys(&:to_s).freeze
      @custom_sorts = sorts.to_h.transform_keys(&:to_s).freeze
      @default_sort = default_sort
    end

    # The contract guarding the query parameters of this listing.
    #
    # The filterable surface is the model's declared one plus every field a
    # custom filter serves; the sortable one is the model's plus every key a
    # custom sort serves. A custom filter's field is not sortable, since no
    # expression orders by it, and a custom sort's key is not filterable.
    #
    # The model's surface is read here and not when the definition is built,
    # so that a definition held in a constant loaded before its model finished
    # declaring still reads the declared list.
    #
    # ==== Returns
    #
    # A Listable::Contract.
    def contract
      Contract.new(
        filterable_fields: model.listable_fields + custom_filters.keys,
        sortable_fields: model.listable_fields + custom_sorts.keys,
        custom_filters: custom_filters,
      )
    end

    # Narrows and orders a relation the way the request asked.
    #
    # The relation is the caller's perimeter and is only ever narrowed, so a
    # client filter cannot widen what the caller resolved. The request is
    # expected to have passed #contract first: the engine raises on a field or
    # a key it was not declared, rather than answer a listing wider than the
    # client asked for.
    #
    # ==== Parameters
    #
    # * +relation+ - the relation to narrow, of the definition's model
    # * +filters+ - the filters parameter as the client sent it
    # * +sort+ - the sort parameter as the client sent it; a blank one is
    #   the default sort, when the definition declares one
    #
    # ==== Returns
    #
    # The narrowed, ordered relation.
    def apply(relation, filters:, sort:)
      relation
        .filtering(Conditions.new(filters).to_a, custom_filters)
        .sorting(sort.presence || default_sort, custom_sorts)
    end

    private

    # The model the listing reads.
    #
    # ==== Returns
    #
    # A class including Listable.
    attr_reader :model

    # The custom filters, by the field they serve.
    #
    # ==== Returns
    #
    # A frozen hash keyed by string.
    attr_reader :custom_filters

    # The custom sorts, by the key they serve.
    #
    # ==== Returns
    #
    # A frozen hash keyed by string.
    attr_reader :custom_sorts

    # The sort parameter a request naming none is ordered by.
    #
    # ==== Returns
    #
    # A string, or +nil+ for the gem's default order.
    attr_reader :default_sort
  end
end
