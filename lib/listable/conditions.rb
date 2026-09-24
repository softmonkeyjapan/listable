# frozen_string_literal: true

module Listable
  # Turns a raw filters payload into the positional list of conditions the
  # filtering engine reads.
  #
  # The format is positional rather than keyed by field name because a map
  # keyed by field name cannot carry two conditions on the same field, and a
  # range on one field is exactly that: two conditions on that field. Two
  # shapes say the same list — the hash a query string parses into, whose keys
  # are the indices the client sent, and the array a programmatic caller
  # passes. Anything else yields the empty list, never a partially read one.
  #
  # The normaliser answers the engine's vocabulary and nothing else: three
  # keys, stripped where the contract expects them stripped, and conditions it
  # cannot read dropped rather than repaired.
  class Conditions
    # The pattern an index key must match.
    #
    # It is read here and by the validation contract, which decides on it
    # whether a payload is a positional list at all. The two must agree on one
    # pattern: widening either alone lets the contract accept a payload this
    # normaliser then empties, answering a client a success that filtered
    # nothing at all. The anchors are +\A+ and +\z+ and not +^+ and +$+, which
    # match around a newline and would read <tt>"0\nname"</tt> as an index.
    INDEX = /\A\d+\z/

    # Holds a raw payload waiting to be read.
    #
    # ==== Parameters
    #
    # * +payload+ - the filters payload as a query string parsed it or as a
    #   programmatic caller passed it
    def initialize(payload)
      @payload = payload
    end

    # Reads the payload as the list of conditions the engine applies.
    #
    # This is the whole public surface of the object: a payload goes in, a
    # clean ordered list comes out, and the conditions the normaliser could not
    # read are gone rather than half-formed. Dropping is deliberate — a
    # condition naming no field or no operator is a client mistake the contract
    # either refused already or deliberately left alone, and raising here would
    # turn a bad query string into a replayable server error.
    #
    # ==== Returns
    #
    # An array of conditions, each a hash carrying +:field+, +:operator+ and,
    # when the payload carried one, +:value+.
    def to_a
      entries.filter_map { |entry| condition(entry) }
    end

    private

    # The raw payload this normaliser was handed.
    #
    # ==== Returns
    #
    # Whatever the caller passed, of whatever type.
    attr_reader :payload

    # Reads the payload's entries in the order the list means.
    #
    # An array is already the list. A hash is the list an indexed query string
    # parsed into. Every other type — a string, a number, nil, an object that
    # is neither — is not a payload this format defines, and it yields nothing
    # rather than an attempt to coerce it into something: coercion there would
    # invent conditions no client sent.
    #
    # ==== Returns
    #
    # An array of the payload's raw entries.
    def entries
      return payload if payload.is_a?(Array)
      return indexed(payload) if payload.is_a?(Hash)

      []
    end

    # Reads an indexed hash as a list, or refuses the whole of it.
    #
    # One non-numeric key is enough to refuse the payload entire, and the
    # temptation to keep the numeric keys and drop the odd one out is the bug
    # this guard exists against: a hash carrying a key that is not an index is
    # the map keyed by field name that this format replaces, and reading half
    # of it would narrow a listing by some of what the client sent while
    # reporting nothing about the rest. An empty list is the honest reading —
    # the client's payload is in a format the engine does not speak, and the
    # contract is the place that says so.
    #
    # The ordering is the one the validation contract reports its refusals in,
    # down to the tie-break: the contract attributes a message to the index the
    # client sent, and a client lines those messages up against this list. Two
    # keys that differ as strings and agree as numbers — <tt>"7"</tt> and
    # <tt>"007"</tt> — therefore keep arrival order here as they do there,
    # rather than an order nothing decides.
    #
    # The indices are the positions, which is what makes the two accepted
    # shapes mean the same list: entries are ordered by the index the client
    # sent, and the indices need not be contiguous because a client dropping
    # one condition out of a form leaves a hole rather than renumbering.
    #
    # ==== Parameters
    #
    # * +hash+ - the payload, known to be a hash
    #
    # ==== Returns
    #
    # An array of the hash's entries ordered by index, or an empty array when
    # any key is not an index.
    def indexed(hash)
      return [] unless hash.keys.all? { |key| key.to_s.match?(INDEX) }

      hash
        .sort_by.with_index { |(index, _entry), position| [index.to_s.to_i, position] }
        .map(&:last)
    end

    # Normalises one entry into the condition the engine reads.
    #
    # Field and operator are stripped here, and here is the only place they are
    # stripped. The validation contract validates them stripped, so a padded
    # operator passes validation; the engine strips nothing and matches
    # <tt>" = "</tt> against no operator function, drops the condition in
    # silence and hands back a listing wider than the client asked for that
    # looks exactly like a filtered one. Stripping at the single point both
    # sides pass through is what keeps the two from disagreeing.
    #
    # The condition is rebuilt from the three keys the format defines rather
    # than copied and pruned, so a key the format does not define cannot
    # survive whatever it is called.
    #
    # The +:value+ key is carried over only when the entry had one. A value set
    # to nil or to the empty string is a value the client sent; a missing key
    # is not, and the contract tells the two apart. Folding them together here
    # would make a condition that forgot its value indistinguishable from one
    # that asked about an empty one.
    #
    # ==== Parameters
    #
    # * +entry+ - one raw entry of the payload
    #
    # ==== Returns
    #
    # A condition hash, or +nil+ when the entry is not one.
    def condition(entry)
      return nil unless entry.respond_to?(:symbolize_keys)

      parts = entry.symbolize_keys
      field = part(parts[:field])
      operator = part(parts[:operator])
      return nil if field.empty? || operator.empty?

      normalised = { field: field, operator: operator }
      normalised[:value] = parts[:value] if parts.key?(:value)
      normalised
    end

    # Reads one part of a condition as a stripped string.
    #
    # A missing part becomes the empty string rather than +nil+, so that the
    # caller has one emptiness to test instead of two.
    #
    # ==== Parameters
    #
    # * +part+ - the raw field or operator as the payload carried it
    #
    # ==== Returns
    #
    # The part as a stripped string.
    def part(part)
      part.to_s.strip
    end
  end
end
