# frozen_string_literal: true

module Listable
  # Orders a relation by the keys a client asked for.
  #
  # The whole object exists to answer one question — what does the +ORDER BY+
  # of this listing read — and it answers it entirely. PostgreSQL guarantees no
  # row order without an +ORDER BY+, and a listing is read page by page, so an
  # order that leaves ties undecided is not an aesthetic matter: it is rows
  # repeated and rows skipped between two pages of the same listing.
  class Sorting
    # The marker a client puts in front of a key to ask for descending order.
    #
    # The direction rides along with the key rather than living in a second
    # parameter, because a client naming several keys has one direction per key
    # and a single +direction+ parameter could only carry one of them.
    DESCENDING = "-"

    # What separates two keys in the wire format.
    SEPARATOR = ","

    # The column the default order reads first when the table carries it.
    TIMESTAMP = "created_at"

    # Holds an ordering in progress.
    #
    # ==== Parameters
    #
    # * +relation+ - the relation to order
    # * +sort+ - the sort parameter as the client sent it
    def initialize(relation, sort)
      @relation = relation
      @sort = sort
    end

    # Applies the order this listing must come back in.
    #
    # The orderings replace whatever order the relation carried rather than
    # queueing behind it. An order left on the relation upstream would
    # otherwise dominate every key the client sent, and the listing would come
    # back in an order the client did not ask for while looking exactly like
    # one that honoured the request. Narrowing is the host's to compose with —
    # ordering is the one decision this call owns outright.
    #
    # ==== Returns
    #
    # The ordered relation.
    def apply
      relation.reorder(*orderings)
    end

    private

    # The relation the ordering started from.
    #
    # ==== Returns
    #
    # An Active Record relation.
    attr_reader :relation

    # The sort parameter exactly as the client sent it.
    #
    # ==== Returns
    #
    # Whatever the caller passed, usually a string.
    attr_reader :sort

    # Builds the full list of orderings the relation is given.
    #
    # A client sort replaces the default order instead of appending to it: a
    # client that named a key means that key to decide the listing, and a
    # default order kept in front of it would demote every key it sent to a
    # tie-breaker of the gem's own choice.
    #
    # ==== Returns
    #
    # An array of Arel ordering nodes, never empty.
    def orderings
      return default_orderings if terms.empty?

      terms.map { |key, descending| ordering(key, descending) } + tie_breaker
    end

    # The ordering the primary key is appended with, when it is appended.
    #
    # This is the tie-breaker that makes the order total, and it is the exact
    # line a reader is tempted to delete as redundant — the client's keys are
    # already there, the rows already come back in the right order, and the
    # appended key changes nothing a single unpaginated query can show. It
    # changes everything a paginated one shows: PostgreSQL orders rows sharing
    # a sort value however the plan it chose happens to emit them, and the plan
    # of <tt>LIMIT 10</tt> is not the plan of <tt>LIMIT 10 OFFSET 10</tt>. A
    # listing ordered on a low-cardinality field then hands the same row to two
    # consecutive pages and never shows another one at all. The primary key is
    # unique, so appending it leaves no tie for the plan to decide.
    #
    # It is built off the table and not through the field resolver on purpose:
    # the declared surface governs what a client may name, and totality is not
    # something a client asks for. A model that does not declare its primary
    # key as listable still gets it appended here.
    #
    # ==== Returns
    #
    # An array holding the primary key's descending ordering, or an empty array
    # when the client already ordered on the primary key and appending it again
    # would only repeat what the order already decides.
    def tie_breaker
      return [] if terms.any? { |key, _| key == model.primary_key }

      [primary_key_ordering]
    end

    # Builds the order a listing comes back in when the client named nothing.
    #
    # The newest rows first is what a listing endpoint is read for, and the
    # primary key behind it keeps that order total the same way it does for a
    # client's keys. A table with no creation timestamp falls back to the
    # primary key alone rather than ordering on a column that is not there: the
    # gem carries the ordering of its consumers' listings, not a timestamp
    # convention they have to adopt to be ordered at all.
    #
    # ==== Returns
    #
    # An array of Arel ordering nodes.
    def default_orderings
      return [primary_key_ordering] unless model.column_names.include?(TIMESTAMP)

      [model.arel_table[TIMESTAMP].desc, primary_key_ordering]
    end

    # Builds the descending ordering of the model's primary key.
    #
    # ==== Returns
    #
    # An Arel ordering node.
    def primary_key_ordering
      model.arel_table[model.primary_key].desc
    end

    # Builds the ordering one term asks for.
    #
    # The expression comes from the same resolver a filter's predicate compares
    # against, so a translated attribute is ordered on the locale extraction its
    # reader would read rather than on the JSON document the column holds —
    # ordering on the document would sort the rows by a serialised object and
    # answer an order that matches nothing the client can see.
    #
    # ==== Parameters
    #
    # * +key+ - the key as the client sent it, marker removed
    # * +descending+ - whether the client asked for descending order
    #
    # ==== Returns
    #
    # An Arel ordering node.
    def ordering(key, descending)
      expression = resolve(key).expression

      descending ? expression.desc : expression.asc
    end

    # Resolves one key through the resolver filtering already goes through.
    #
    # The resolution is not repeated here, only its refusal is renamed: the
    # surface a sort key crosses is the sort surface, and a caller rescuing the
    # failure needs to know which of the two it crossed. Renaming rather than
    # re-implementing keeps the fail-closed check in the one place that owns it,
    # so a key no whitelist carries cannot come back merely unordered.
    #
    # ==== Parameters
    #
    # * +key+ - the key as the client sent it, marker removed
    #
    # ==== Returns
    #
    # A Field.
    #
    # ==== Raises
    #
    # UnknownKey when the model does not declare the key, or declares it and
    # carries neither a translated attribute nor a column of that name.
    def resolve(key)
      resolver.resolve(key)
    rescue UnknownField => error
      raise UnknownKey, error.message
    end

    # Reads the keys the client sent, in the order they were sent.
    #
    # The order of the list is the client's: keys break each other's ties the
    # way the client arranged them, and re-arranging them would answer a
    # listing ordered by something nobody asked for.
    #
    # ==== Returns
    #
    # An array of <tt>[key, descending]</tt> pairs, possibly empty.
    def terms
      @terms ||= sort.to_s.split(SEPARATOR).filter_map { |term| term_of(term) }
    end

    # Reads one term of the wire format.
    #
    # Whitespace around a term and between the marker and the key is tolerated,
    # because a hand-written query string carries it and a client that typed
    # <tt>"- name"</tt> asked for the same thing as one that typed
    # <tt>"-name"</tt>. A term naming nothing — blank, or nothing but the
    # descending marker — is dropped rather than resolved: it names no key, so
    # there is no key to refuse, and a sort that names nothing at all leaves the
    # default order standing.
    #
    # ==== Parameters
    #
    # * +term+ - one comma-separated term of the sort parameter
    #
    # ==== Returns
    #
    # A <tt>[key, descending]</tt> pair, or +nil+ when the term names no key.
    def term_of(term)
      stripped = term.strip
      descending = stripped.start_with?(DESCENDING)
      key = stripped.delete_prefix(DESCENDING).strip

      key.empty? ? nil : [key, descending]
    end

    # The Active Record class the keys are resolved against.
    #
    # ==== Returns
    #
    # The model class of the relation being ordered.
    def model
      relation.klass
    end

    # The resolver every key of this ordering goes through.
    #
    # ==== Returns
    #
    # A FieldResolver bound to the relation's model.
    def resolver
      @resolver ||= FieldResolver.new(model)
    end
  end
end
