# frozen_string_literal: true

module Listable
  # Guards the query parameters of a listing before a single predicate is built.
  #
  # It is the layer that turns a bad request into a 422 naming what to fix,
  # rather than into a 500 raised deep inside pagination or — worse — into a
  # listing that quietly came back wider than the client asked to see.
  #
  # The two field surfaces are required options with no default. A contract
  # that does not know the surface cannot guard it, and a default would be a
  # bypass nobody would notice: every request would pass. They are two options
  # rather than one because they are genuinely two lists — a listing may accept
  # a filter on a field that is not a column, served by a custom filter, and a
  # field that is not a column cannot be ordered by.
  #
  # Both parameters are optional and deliberately untyped. The payload is a
  # hash on the wire and an array from a programmatic caller, and the sort is
  # always a string on the wire but is refused rather than coerced when it is
  # not one: coercing +["name"]+ into +"name"+ would answer a listing sorted by
  # something the client never asked for.
  class Contract < Dry::Validation::Contract
    # The most conditions one request may carry.
    #
    # The cap is what keeps the endpoint predictable under a generated query:
    # without it a client can hand the engine an arbitrary number of predicates
    # to build and PostgreSQL an arbitrary number to plan.
    MAX_CONDITIONS = 20

    # The message keys this contract can emit, and no others.
    #
    # The vocabulary is closed and enumerated here because the suite reads it:
    # every key below is checked against every locale the gem ships. A key
    # added to a rule and forgotten in a locale file would otherwise reach a
    # host's production as a +translation missing+ string served to its client.
    MESSAGE_KEYS = %i[
      list? hash? too_many
      field_required field_scalar field_unknown
      operator_required operator_scalar operator_invalid
      value_required value_scalar value_list
      unknown_key?
      sort_scalar sort_unknown
    ].freeze

    # The locale files the gem ships its messages in.
    #
    # They are globbed rather than listed so that adding a language is adding a
    # file. The glob reads the packaged gem, which is why the gemspec ships
    # +config/locales+ alongside +lib+: a locale file left out of the package
    # makes this list shorter in the host than it is here, and every message
    # the host serves becomes a missing translation without one test in this
    # repository turning red.
    MESSAGE_PATHS = Dir.glob(File.expand_path("../../config/locales/*.yml", __dir__)).freeze

    # The backend is set on this contract and not through the global
    # dry-validation configuration. A host whose own contracts resolve their
    # messages some other way must not have that changed by installing a gem,
    # and a host that configured nothing at all must still read real messages
    # rather than the keys.
    #
    # The namespace is the gem's own for the same reason: +listable.errors+
    # cannot collide with the messages a host writes for its own contracts, and
    # it is the namespace the railtie puts on the application's i18n load path,
    # which is how a host overrides a single message by loading a file after
    # the gem's.
    #
    # No default locale is set, so messages follow the locale the request is
    # served in rather than one the gem chose.
    config.messages.backend = :i18n
    config.messages.top_namespace = "listable"
    config.messages.load_paths += MESSAGE_PATHS

    # Key validation stays off. The payload's own keys are the indices the
    # client sent, which no schema can enumerate, and the keys of a condition
    # are checked by the rule below — where a stray key earns one attributed
    # message instead of an anonymous one on the whole parameter.
    config.validate_keys = false

    # The field names this listing accepts a filter on.
    option :filterable_fields

    # The field names this listing accepts an order on.
    option :sortable_fields

    # Both parameters are declared and left untyped on purpose: the two shapes
    # a payload arrives in are not one type, and a sort that is not a string is
    # refused by its rule with a message rather than coerced by the schema in
    # silence.
    params do
      optional(:filters)
      optional(:sort)
    end

    # Refuses the filters payload, either whole or condition by condition.
    #
    # The two kinds of refusal never mix, and the +next+ below is what keeps
    # them apart: a payload that is not a positional list has no conditions to
    # attribute anything to, so reporting it once on the parameter is the only
    # honest answer. Reporting it and then walking the payload anyway would
    # answer a client both "this is not a list" and a message per element of
    # the thing that is not a list.
    #
    # Per-condition refusals carry the index the client sent, holes included,
    # so that a client reading the response can map every message back to the
    # condition it belongs to. A condition contributes one failure per mistake
    # it carries, all under that one index: the index is what makes a payload
    # of malformed conditions readable, so there is nothing to gain by
    # withholding a client's second mistake until it has fixed its first.
    rule(:filters) do
      payload = values[:filters]
      next if payload.blank?

      refusal = payload_refusal(payload)
      next key.failure(*refusal) if refusal

      condition_refusals(payload).each do |index, (message, tokens)|
        key([:filters, index]).failure(message, tokens)
      end
    end

    # Refuses the sort parameter, once for the whole of it.
    #
    # One failure and not one per key: the message enumerates the surface a
    # client may order by, so a client naming three undeclared keys would read
    # the same list of allowed keys three times and learn nothing the first one
    # did not already say.
    #
    # The failure lands on +sort+ and can never land under +filters+, because a
    # client that sent both has to be able to tell which of the two it got
    # wrong.
    rule(:sort) do
      sort = values[:sort]
      next if sort.nil?
      next key.failure(:sort_scalar) unless sort.is_a?(String)
      next if unknown_sort_keys(sort).empty?

      key.failure(:sort_unknown, fields: sortable_fields)
    end

    private

    # Names what is wrong with the payload taken as a whole.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters parameter as the client sent it
    #
    # ==== Returns
    #
    # A <tt>[message key, tokens]</tt> pair, or +nil+ when the payload is a
    # positional list within the cap.
    def payload_refusal(payload)
      return [:list?, {}] unless positional?(payload)
      return [:too_many, { cap: MAX_CONDITIONS }] if entries(payload).size > MAX_CONDITIONS

      nil
    end

    # Tells whether the payload is a positional list at all.
    #
    # The index pattern is the normaliser's own, read from it rather than
    # written again here. The two have to agree on one pattern: widening this
    # one alone would let the contract accept a payload the normaliser then
    # reads as the empty list, and the client would be answered a success by a
    # listing that filtered nothing. A map keyed by field name — the format the
    # positional one replaces — fails here, which is the whole reason the check
    # exists.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters parameter as the client sent it
    #
    # ==== Returns
    #
    # +true+ when the payload is an array or a hash keyed by indices.
    def positional?(payload)
      return true if payload.is_a?(Array)
      return false unless payload.is_a?(Hash)

      payload.keys.all? { |key| key.to_s.match?(Conditions::INDEX) }
    end

    # Pairs every condition with the index the client gave it.
    #
    # The index is reported exactly as it arrived, and that is the whole
    # contract of this method: a client matches a message back to the condition
    # it sent by comparing this key to the one it wrote. Reading the key as a
    # number and reporting the number breaks that correspondence the moment the
    # client writes anything but the canonical form — <tt>filters[007]</tt>
    # comes back attributed to <tt>7</tt>, an index the client never sent, and
    # matching by key fails at the one thing the positional format exists to
    # make possible.
    #
    # Ordering and reporting therefore read different values. The entries are
    # ordered by the numeric value of the index, because a payload is a
    # positional list and its refusals read in the order the client wrote its
    # conditions; the key handed back is the untouched one. The position within
    # the payload breaks a tie, so two keys that differ as strings and agree as
    # numbers — <tt>"7"</tt> and <tt>"007"</tt> — keep arrival order instead of
    # an order nothing decides.
    #
    # An array's index is its position, rendered as a string like a hash's key.
    # The two accepted shapes must report the same type or an in-process caller
    # reading the result hash has to know which shape its own web layer parsed
    # the request into.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters parameter, known to be a positional list
    #
    # ==== Returns
    #
    # An array of <tt>[index, entry]</tt> pairs, the index a string.
    def entries(payload)
      return positions(payload) if payload.is_a?(Array)

      payload
        .map { |index, entry| [index.to_s, entry] }
        .sort_by.with_index { |(index, _entry), position| [index.to_i, position] }
    end

    # Pairs every condition of an array payload with its position.
    #
    # The position is rendered as a string so that an array payload and a hash
    # payload report the same type of key. An in-process caller reading the
    # result hash would otherwise have to know which of the two shapes its own
    # web layer parsed the request into before it could look a refusal up.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters parameter, known to be an array
    #
    # ==== Returns
    #
    # An array of <tt>[index, entry]</tt> pairs, the index a string.
    def positions(payload)
      payload.each_with_index.map { |entry, index| [index.to_s, entry] }
    end

    # Names everything that is wrong with each condition that is wrong.
    #
    # A condition contributes as many pairs as it has mistakes, all carrying
    # the same index, and the caller posts one failure per pair under that one
    # key. dry-validation accumulates several failures on a key rather than
    # replacing the previous one, which is what lets a client read that its
    # field is blank *and* that its operator is not one the gem knows — two
    # corrections it can make before sending the request again.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters parameter, known to be a positional list
    #
    # ==== Returns
    #
    # An array of <tt>[index, refusal]</tt> pairs, in the order a client reads
    # them.
    def condition_refusals(payload)
      entries(payload).flat_map do |index, entry|
        ConditionCheck.new(entry, filterable_fields).refusals.map { |refusal| [index, refusal] }
      end
    end

    # Reads the sort keys the client named and keeps the undeclared ones.
    #
    # The parameter is split on the separator the sorting engine splits on and
    # stripped of the marker the sorting engine reads, both taken from that
    # engine rather than spelled again: a contract that parsed the wire format
    # its own way would either refuse a key the engine orders by perfectly
    # well, or accept one the engine then resolves against no whitelist at all
    # and raises on. A term naming nothing is dropped rather than refused,
    # because a sort that names nothing leaves the default order standing.
    #
    # ==== Parameters
    #
    # * +sort+ - the sort parameter, known to be a string
    #
    # ==== Returns
    #
    # An array of the keys the sortable surface does not carry.
    def unknown_sort_keys(sort)
      allowed = sortable_fields.map(&:to_s)

      sort.split(Sorting::SEPARATOR).filter_map { |term| sort_key(term) }.reject do |key|
        allowed.include?(key)
      end
    end

    # Reads one term of the sort parameter as the key it names.
    #
    # ==== Parameters
    #
    # * +term+ - one separated term of the sort parameter
    #
    # ==== Returns
    #
    # The key the term names, or +nil+ when it names none.
    def sort_key(term)
      key = term.strip.delete_prefix(Sorting::DESCENDING).strip

      key.empty? ? nil : key
    end
  end
end
