# frozen_string_literal: true

module Listable
  # Narrows a relation by a list of conditions.
  #
  # Conditions combine with AND and nothing else. The list is folded over the
  # relation one condition at a time, so that a condition the engine cannot
  # honour disappears on its own and leaves every other one applied: the
  # relation a client gets back is never wider than the conditions the engine
  # could read, and never a failed request because one of them was malformed.
  class Filtering
    # The Arel predication each comparison operator maps onto.
    COMPARISONS = {
      "=" => :eq,
      "!=" => :not_eq,
      ">" => :gt,
      ">=" => :gteq,
      "<" => :lt,
      "<=" => :lteq,
    }.freeze

    # Whether each pattern operator wants its match case-sensitive.
    #
    # Arel's +matches+ visits to +LIKE+ when case-sensitive and to +ILIKE+
    # otherwise on PostgreSQL, which is the whole difference between the two
    # operators the vocabulary offers.
    PATTERNS = { "like" => true, "ilike" => false }.freeze

    # The three words the +is+ operator reads, mapped to what they test.
    #
    # +null+ maps to +nil+ because Arel turns an equality against +nil+ into an
    # +IS NULL+, which is the only form PostgreSQL answers true to.
    WORDS = { "null" => nil, "true" => true, "false" => false }.freeze

    # Holds a narrowing in progress.
    #
    # ==== Parameters
    #
    # * +relation+ - the relation to narrow
    # * +conditions+ - the positional list of conditions
    # * +custom_filters+ - a map of field name to an object answering +apply+
    def initialize(relation, conditions, custom_filters)
      @relation = relation
      @conditions = Array.wrap(conditions)
      @custom_filters = custom_filters.to_h.transform_keys(&:to_s)
    end

    # Applies every condition the engine can honour.
    #
    # ==== Returns
    #
    # The narrowed relation.
    def apply
      conditions.reduce(relation) { |narrowed, condition| narrow(narrowed, condition) }
    end

    private

    # The relation the narrowing started from.
    #
    # ==== Returns
    #
    # An Active Record relation.
    attr_reader :relation

    # The positional list of conditions to apply.
    #
    # ==== Returns
    #
    # An array of conditions.
    attr_reader :conditions

    # The custom filters this call supplied, keyed by field name as a string.
    #
    # ==== Returns
    #
    # A hash of field name to filter object.
    attr_reader :custom_filters

    # Applies one condition to the relation.
    #
    # The custom-filter lookup runs before the field is treated as a column and
    # before the declared surface is consulted, which is what lets a listing
    # filter on an association or a computed perimeter without that name ever
    # entering the model's whitelist — and what lets a custom filter claim a
    # field even when a column of the same name exists. No rescue is wrapped
    # around the call: errors raised inside a host's filter are the host's.
    #
    # ==== Parameters
    #
    # * +narrowed+ - the relation as the previous conditions left it
    # * +condition+ - the condition to apply
    #
    # ==== Returns
    #
    # The relation, narrowed by this condition or untouched.
    def narrow(narrowed, condition)
      field, operator, value = read(condition)
      return narrowed unless known?(field, operator)

      custom = custom_filters[field]
      return custom.apply(narrowed, operator, value) if custom

      built = predicate(resolver.resolve(field), operator, value)
      built ? narrowed.where(built) : narrowed
    end

    # Reads the three parts of a condition.
    #
    # The field and the operator are read as strings and the value is left
    # exactly as it arrived, because a list operator is entitled to an array
    # and every cast reads the raw value. Nothing is stripped here: normalising
    # the payload is the caller's step, and a padded operator that reached the
    # engine is a condition the engine must drop rather than repair — repairing
    # it would hide the normalisation that failed to happen.
    #
    # ==== Parameters
    #
    # * +condition+ - one entry of the positional list
    #
    # ==== Returns
    #
    # An array of the field name, the operator and the raw value.
    def read(condition)
      return [nil, nil, nil] unless condition.respond_to?(:symbolize_keys)

      parts = condition.symbolize_keys

      [parts[:field].to_s, parts[:operator].to_s, parts[:value]]
    end

    # Tells whether a condition names something the vocabulary defines.
    #
    # A blank field, a blank operator and an operator outside the vocabulary
    # are all client mistakes the validation contract either refused already or
    # deliberately left alone, so they drop in silence: raising here would turn
    # a bad query string into a replayable 500.
    #
    # ==== Parameters
    #
    # * +field+ - the field name as read off the condition
    # * +operator+ - the operator as read off the condition
    #
    # ==== Returns
    #
    # +true+ when the condition is worth resolving.
    def known?(field, operator)
      field.present? && operator.present? && OPERATORS.include?(operator)
    end

    # Builds the predicate one condition asks for.
    #
    # ==== Parameters
    #
    # * +field+ - the resolved Field
    # * +operator+ - the operator, known to belong to the vocabulary
    # * +value+ - the raw value as received from the client
    #
    # ==== Returns
    #
    # An Arel predicate, or +nil+ when the condition must be dropped.
    def predicate(field, operator, value)
      case operator
      when "is" then word_predicate(field, value)
      when "in", "not_in" then list_predicate(field, operator, value)
      when "like", "ilike" then pattern_predicate(field, operator, value)
      else comparison_predicate(field, operator, value)
      end
    end

    # Builds the predicate of a comparison operator.
    #
    # This is the only operator family whose value is cast, and the rescue is
    # wrapped around the cast alone: a malformed date or a word where a number
    # was expected drops this one condition and leaves the relation narrowed by
    # every other one. Widening the rescue — around the whole of +apply+, say —
    # would turn a genuine bug in predicate building into an unfiltered listing
    # nobody notices.
    #
    # ==== Parameters
    #
    # * +field+ - the resolved Field
    # * +operator+ - one of the comparison operators
    # * +value+ - the raw value as received from the client
    #
    # ==== Returns
    #
    # An Arel predicate, or +nil+ when the value cannot be cast.
    def comparison_predicate(field, operator, value)
      cast = Casting.call(value, field.cast_type)

      field.expression.public_send(COMPARISONS.fetch(operator), cast)
    rescue Casting::Failure
      nil
    end

    # Builds the predicate of a list operator.
    #
    # A real array arrives from a programmatic caller and is used as it stands;
    # a comma-separated string is what a hand-written query string carries, and
    # each of its elements is stripped so that <tt>"1, 2"</tt> selects two
    # identifiers rather than one identifier and one space-padded miss. The
    # elements are not cast: Arel quotes them through the attribute's own type
    # on the way to the database.
    #
    # ==== Parameters
    #
    # * +field+ - the resolved Field
    # * +operator+ - +in+ or +not_in+
    # * +value+ - an array, or a comma-separated string
    #
    # ==== Returns
    #
    # An Arel predicate.
    def list_predicate(field, operator, value)
      list = value.is_a?(Array) ? value : value.to_s.split(",").map(&:strip)

      operator == "in" ? field.expression.in(list) : field.expression.not_in(list)
    end

    # Builds the predicate of a pattern operator.
    #
    # A pattern operator aimed at a non-textual expression builds nothing at
    # all. PostgreSQL refuses a +LIKE+ against an integer, and because the
    # relation is lazy that refusal does not surface here — it surfaces when
    # the relation is enumerated, somewhere downstream of every rescue, as a
    # 500 answered to a client who only sent a bad query string. Dropping the
    # condition is the only treatment that keeps the failure impossible rather
    # than merely unlikely.
    #
    # The value is coerced to a string and never cast: a pattern is a pattern,
    # and casting <tt>"%10%"</tt> to a number would destroy it.
    #
    # ==== Parameters
    #
    # * +field+ - the resolved Field
    # * +operator+ - +like+ or +ilike+
    # * +value+ - the raw value as received from the client
    #
    # ==== Returns
    #
    # An Arel predicate, or +nil+ when the expression yields no text.
    def pattern_predicate(field, operator, value)
      return nil unless field.textual?

      field.expression.matches(value.to_s, nil, PATTERNS.fetch(operator))
    end

    # Builds the predicate of the null/true/false operator.
    #
    # The value is read stripped and downcased so that <tt>" NULL "</tt> and
    # <tt>"null"</tt> mean the same test, and it is never cast: casting
    # <tt>"null"</tt> against an integer column would raise and drop a
    # condition whose whole purpose is to ask about the absence of a value.
    # Anything outside the three words falls back to plain equality, so the
    # operator stays usable on a field whose vocabulary the client knows better
    # than the gem does.
    #
    # ==== Parameters
    #
    # * +field+ - the resolved Field
    # * +value+ - the raw value as received from the client
    #
    # ==== Returns
    #
    # An Arel predicate.
    def word_predicate(field, value)
      word = value.to_s.strip.downcase

      field.expression.eq(WORDS.key?(word) ? WORDS.fetch(word) : value)
    end

    # The resolver every field of this narrowing goes through.
    #
    # ==== Returns
    #
    # A FieldResolver bound to the relation's model.
    def resolver
      @resolver ||= FieldResolver.new(relation.klass)
    end
  end
end
