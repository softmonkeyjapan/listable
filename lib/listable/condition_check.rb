# frozen_string_literal: true

module Listable
  # Reads one condition of a filters payload and names what is wrong with it.
  #
  # It exists apart from the contract because of one property the contract
  # cannot express in a rule block: a condition earns *at most one* message. A
  # client sending twenty malformed conditions must read twenty messages it can
  # act on, not eighty strings it has to guess the origin of, and a condition
  # whose field is an object must be told its field is an object rather than
  # also being told that object is not a declared field — the second message is
  # noise built on the first.
  #
  # What the check refuses is the shape of a condition, never its meaning: a
  # field the model cannot narrow on with that operator, and a value the engine
  # will fail to cast, both pass. Those are the engine's to drop in silence,
  # and refusing them here would turn a client's mistake into a 422 for a
  # request the engine would have answered.
  class ConditionCheck
    # The three keys a condition is made of, and no others.
    #
    # A key outside this list is refused rather than ignored: it is a typo in a
    # key name, and ignoring it would drop the client's filter while answering
    # a listing that looks filtered.
    KEYS = %i[field operator value].freeze

    # The operators whose value is a list rather than a single value.
    #
    # The distinction is what the value check reads, because arity is a
    # property of the operator and not of the field: +in+ takes several values
    # on any column, +=+ takes one on every column.
    LIST_OPERATORS = %w[in not_in].freeze

    # Holds one raw condition waiting to be read.
    #
    # ==== Parameters
    #
    # * +entry+ - one entry of the filters payload, of whatever type
    # * +fields+ - the field names this listing accepts a filter on
    def initialize(entry, fields)
      @entry = entry
      @fields = fields.map(&:to_s)
    end

    # Names the single thing this condition is refused for.
    #
    # The chain below is the whole point of the object, and the order of its
    # links is a decision rather than a convenience. It runs shape, then keys,
    # then field, then operator, then value, and it stops at the first link
    # that answers, because +||+ is what guarantees one condition earns one
    # message. Reordering it, or turning it into a list of checks whose
    # refusals are all collected, brings back the failure it exists against: a
    # condition whose field is an array answers +field_scalar+ *and*
    # +field_unknown+, a condition carrying a stray key answers that plus every
    # complaint about the three keys it got right, and the client is handed a
    # pile of strings it cannot map back to anything it sent.
    #
    # Within the field and the operator the order is the same reasoning one
    # level down: a container comes before a blank, which comes before an
    # unknown, because reading a container as a string would call it unknown
    # and say nothing about the fact that it is an object.
    #
    # ==== Returns
    #
    # A <tt>[message key, tokens]</tt> pair, or +nil+ when the condition is
    # well-formed.
    def refusal
      shape_refusal || key_refusal || field_refusal || operator_refusal || value_refusal
    end

    private

    # The raw entry this check was handed.
    #
    # ==== Returns
    #
    # Whatever the payload carried at that index, of whatever type.
    attr_reader :entry

    # The field names a filter may name on this listing.
    #
    # ==== Returns
    #
    # An array of strings.
    attr_reader :fields

    # Refuses an entry that is not a condition object at all.
    #
    # It is the first link of the chain because every link after it reads keys,
    # and a string or a number carries none. The test is the one the normaliser
    # applies, so the contract accepts exactly the entries the normaliser can
    # read.
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the entry is an object.
    def shape_refusal
      [:hash?, {}] unless entry.respond_to?(:symbolize_keys)
    end

    # Refuses a condition carrying a key the format does not define.
    #
    # It runs before the three keys are read so that a client that misspelled
    # +operator+ is told about the key it invented, and not about the operator
    # it appears not to have sent.
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the condition carries nothing else.
    def key_refusal
      [:unknown_key?, {}] unless (parts.keys - KEYS).empty?
    end

    # Refuses the field, on the one ground that applies first.
    #
    # The field is read stripped, because the normaliser strips it: validating
    # the padded form would accept <tt>" name "</tt> here and hand the engine a
    # field it then narrows on, or refuse a field the normaliser would have
    # read perfectly well.
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the field is a declared one.
    def field_refusal
      raw = parts[:field]
      return [:field_scalar, {}] if container?(raw)

      name = stripped(raw)
      return [:field_required, {}] if name.empty?
      return [:field_unknown, { fields: fields }] unless fields.include?(name)

      nil
    end

    # Refuses the operator, on the one ground that applies first.
    #
    # The operator is read stripped for the reason the field is: the normaliser
    # strips it, and an operator validated padded matches no operator function
    # afterwards, dropping the condition in silence.
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the operator is one of the vocabulary's.
    def operator_refusal
      raw = parts[:operator]
      return [:operator_scalar, {}] if container?(raw)

      name = stripped(raw)
      return [:operator_required, {}] if name.empty?
      return [:operator_invalid, {}] unless OPERATORS.include?(name)

      nil
    end

    # Refuses the value on the arity the operator asks for.
    #
    # This is the load-bearing check of the whole contract, and the one a
    # reader is most tempted to drop as over-validation: nothing reads the
    # value here, so refusing an array looks like refusing a shape that would
    # have worked. It would not have worked. A non-scalar value handed to a
    # single-value operator reaches Arel, and because the relation is lazy the
    # refusal does not come out of the query builder — it fires while the rows
    # are being enumerated, downstream of every rescue the host wrapped around
    # building the listing, and the client that sent a bad query string reads a
    # 500. Refused here, it reads a 422 naming the condition.
    #
    # What decides the arity is the operator and not the field's type. A value
    # the field cannot hold is the engine's business to drop; a value the
    # operator cannot receive is this one's.
    #
    # A missing +value+ key and a value set to nil are told apart on purpose: a
    # client that sent <tt>value=</tt> asked about the empty string, and one
    # that sent no +value+ at all sent an incomplete condition.
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the value suits the operator's arity.
    def value_refusal
      return [:value_required, {}] unless parts.key?(:value)

      raw = parts[:value]
      return list_refusal(raw) if LIST_OPERATORS.include?(stripped(parts[:operator]))
      return [:value_scalar, {}] if container?(raw)

      nil
    end

    # Refuses the value of a list operator.
    #
    # A list operator reads either a real array or the comma-separated string a
    # hand-written query string carries, so a single value is accepted here and
    # split downstream. What is refused is a nesting the engine cannot quote: a
    # map, or a list one of whose elements is itself a container.
    #
    # ==== Parameters
    #
    # * +raw+ - the value as the payload carried it
    #
    # ==== Returns
    #
    # A refusal pair, or +nil+ when the value is a flat list or a single value.
    def list_refusal(raw)
      return [:value_list, {}] if raw.is_a?(Hash)
      return [:value_list, {}] if raw.is_a?(Array) && raw.any? { |element| container?(element) }

      nil
    end

    # Reads the entry's keys the way the normaliser reads them.
    #
    # Symbolising is what lets one check answer both shapes the payload arrives
    # in — the string keys of a parsed query string and the symbol keys of a
    # programmatic caller — without the rest of the object asking twice.
    #
    # ==== Returns
    #
    # The entry as a hash with symbol keys.
    def parts
      @parts ||= entry.symbolize_keys
    end

    # Tells whether a part of a condition is a container rather than a value.
    #
    # ==== Parameters
    #
    # * +part+ - a field, an operator or a value as the payload carried it
    #
    # ==== Returns
    #
    # +true+ when the part is a map or a list.
    def container?(part)
      part.is_a?(Hash) || part.is_a?(Array)
    end

    # Reads a part of a condition as the normaliser would read it.
    #
    # ==== Parameters
    #
    # * +part+ - a field or an operator as the payload carried it
    #
    # ==== Returns
    #
    # The part as a stripped string.
    def stripped(part)
      part.to_s.strip
    end
  end
end
