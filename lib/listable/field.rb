# frozen_string_literal: true

module Listable
  # What the engine needs to know about a field before it builds a predicate.
  #
  # The members are kept together because they are decided together and must
  # not be re-derived at the point of use. +expression+ is not always the
  # column — a translated attribute compares through a locale extraction —
  # which is exactly why +textual+, +cast_type+ and +attribute_type+ cannot be
  # looked back up from the expression: a reader who tried would land on the
  # JSON column and reintroduce both the comparison against a whole document
  # and the refusal of the pattern operators the extraction is entitled to.
  Field = Data.define(:expression, :textual, :cast_type, :attribute_type) do
    # Tells whether a pattern operator may build a predicate on the expression.
    #
    # ==== Returns
    #
    # +true+ when the expression yields text, +false+ otherwise.
    def textual?
      textual
    end

    # Tells whether a value can reach the database through the expression.
    #
    # The question goes to the attribute's own type because that type is what
    # serialises the value when the predicate turns into SQL, and what raises
    # +ActiveModel::RangeError+ when it cannot. A constant here would refuse
    # what a +bigint+ column can hold. A type with no range answers +true+ to
    # anything, and a non-numeric string reads as a number the range contains,
    # so neither is mistaken for a value too large to store.
    #
    # ==== Parameters
    #
    # * +value+ - the value about to be compared
    #
    # ==== Returns
    #
    # +false+ when no row of the column can hold the value, +true+ otherwise.
    def holds?(value)
      attribute_type.serializable?(value)
    end
  end
end
