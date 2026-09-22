# frozen_string_literal: true

module Listable
  # What the engine needs to know about a field before it builds a predicate.
  #
  # The three members are kept together because they are decided together and
  # must not be re-derived at the point of use. +expression+ is not always the
  # column — a translated attribute compares through a locale extraction —
  # which is exactly why +textual+ and +cast_type+ cannot be looked back up
  # from the expression: a reader who tried would land on the JSON column and
  # reintroduce both the comparison against a whole document and the refusal of
  # the pattern operators the extraction is entitled to.
  Field = Data.define(:expression, :textual, :cast_type) do
    # Tells whether a pattern operator may build a predicate on the expression.
    #
    # ==== Returns
    #
    # +true+ when the expression yields text, +false+ otherwise.
    def textual?
      textual
    end
  end
end
