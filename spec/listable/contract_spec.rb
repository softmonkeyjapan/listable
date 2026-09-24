# frozen_string_literal: true

RSpec.describe Listable::Contract do
  # The contract every example validates against.
  #
  # The two surfaces differ on purpose. +owner+ is filterable without being a
  # column, the way a field served by a custom filter is, and +quantity+ is
  # filterable without being sortable, so no example can pass by confusing the
  # two lists for one.
  #
  # ==== Returns
  #
  # A contract bound to the suite's two surfaces.
  def contract
    described_class.new(
      filterable_fields: %w[id name quantity owner],
      sortable_fields: %w[id name],
    )
  end

  # Validates a set of parameters and reports what they earned.
  #
  # This is the seam the suite is allowed to touch: parameters go in, the
  # messages a client would read come out, and nothing inside the contract is
  # reached for.
  #
  # ==== Parameters
  #
  # * +params+ - the listing parameters as the client sent them
  #
  # ==== Returns
  #
  # The errors as a hash, empty when the parameters passed.
  def refusals(params)
    contract.call(params).errors.to_h
  end

  # Reads a message out of the locale files the gem ships.
  #
  # The examples compare against the shipped text rather than against a string
  # spelled again here, so that rewording a message stays one edit in one file
  # instead of a suite-wide rename.
  #
  # ==== Parameters
  #
  # * +key+ - the message key
  # * +tokens+ - the interpolations the message takes
  #
  # ==== Returns
  #
  # The message as a client would read it.
  def message(key, **tokens)
    I18n.t("listable.errors.#{key}", **tokens)
  end

  # The filterable surface, rendered the way a message enumerates it.
  #
  # ==== Returns
  #
  # The filterable field names joined the way the message backend joins them.
  def filterable
    "id, name, quantity, owner"
  end

  # The sortable surface, rendered the way a message enumerates it.
  #
  # ==== Returns
  #
  # The sortable field names joined the way the message backend joins them.
  def sortable
    "id, name"
  end

  # The contract stores its messages into the i18n backend the first time it is
  # built, so an example reading a message directly needs one to exist first.
  before { contract }

  describe "the two required surfaces" do
    it "refuses to be built without a filterable surface" do
      expect { described_class.new(sortable_fields: []) }.to raise_error(KeyError)
    end

    it "refuses to be built without a sortable surface" do
      expect { described_class.new(filterable_fields: []) }.to raise_error(KeyError)
    end

    # A listing may accept a filter on a field it cannot order by, which is the
    # whole reason the contract takes two lists instead of one.
    it "accepts as a filter a field the sortable surface does not carry" do
      expect(refusals(filters: [{ field: "quantity", operator: "=", value: "3" }])).to be_empty
    end

    it "refuses as a sort a field only the filterable surface carries" do
      expect(refusals(sort: "quantity")).to eq(sort: [message(:sort_unknown, fields: sortable)])
    end
  end

  describe "parameters that are absent or blank" do
    it "passes parameters that are absent altogether" do
      expect(refusals({})).to be_empty
    end

    it "passes a blank payload and a blank sort" do
      expect(refusals(filters: [], sort: "")).to be_empty
      expect(refusals(filters: {}, sort: "")).to be_empty
      expect(refusals("filters" => "", "sort" => "")).to be_empty
    end

    it "passes a well-formed payload" do
      payload = [
        { field: "quantity", operator: ">=", value: "3" },
        { field: "name", operator: "ilike", value: "%ask%" },
      ]

      expect(refusals(filters: payload, sort: "-name,id")).to be_empty
    end
  end

  describe "a payload that is not a positional list" do
    # The map keyed by field name is the format the positional one replaces,
    # and it is refused once on the parameter rather than walked: there is no
    # condition to attribute anything to inside a payload the format does not
    # define.
    it "refuses a map keyed by field name, once, on the filters parameter" do
      payload = { "name" => { "operator" => "=", "value" => "Gasket" } }

      expect(refusals("filters" => payload)).to eq(filters: [message(:list?)])
    end

    it "refuses a payload that is neither a list nor a map" do
      expect(refusals(filters: "name=Gasket")).to eq(filters: [message(:list?)])
    end

    it "refuses a map whose keys are not all indices" do
      payload = { "0" => { field: "id", operator: "=", value: "1" }, "name" => "Gasket" }

      expect(refusals("filters" => payload)).to eq(filters: [message(:list?)])
    end
  end

  describe "the condition cap" do
    it "refuses a payload beyond the cap, once, naming the cap" do
      cap = described_class::MAX_CONDITIONS
      payload = Array.new(cap + 1) { { field: "id", operator: "=", value: "1" } }

      expect(refusals(filters: payload)).to eq(filters: [message(:too_many, cap: cap)])
    end

    it "passes a payload sitting exactly on the cap" do
      payload = Array.new(described_class::MAX_CONDITIONS) do
        { field: "id", operator: "=", value: "1" }
      end

      expect(refusals(filters: payload)).to be_empty
    end
  end

  describe "attribution" do
    it "attributes a refusal to the position of the condition in a list" do
      payload = [
        { field: "id", operator: "=", value: "1" },
        { field: "secret", operator: "=", value: "1" },
      ]

      expect(refusals(filters: payload)).to eq(
        filters: { 1 => [message(:field_unknown, fields: filterable)] },
      )
    end

    # A client that dropped one condition out of a form leaves a hole behind
    # rather than renumbering what it kept, and it has to be able to map the
    # message back to the index it sent.
    it "attributes a refusal to the index the client sent, holes included" do
      payload = {
        "0" => { field: "id", operator: "=", value: "1" },
        "7" => { field: "secret", operator: "=", value: "1" },
      }

      expect(refusals("filters" => payload)).to eq(
        filters: { 7 => [message(:field_unknown, fields: filterable)] },
      )
    end

    it "gives every wrong condition of a payload its own message" do
      payload = [
        { field: "secret", operator: "=", value: "1" },
        { field: "id", operator: "=", value: "1" },
        { field: "id", operator: "~", value: "1" },
      ]

      expect(refusals(filters: payload).fetch(:filters).keys).to eq([0, 2])
    end
  end

  # Each condition below carries exactly one mistake, so each answers exactly
  # one message. What that pins is the bound inside a family of checks — a
  # container is reported as a container and not also as an undeclared name —
  # and not a bound on the condition, which answers every mistake it carries.
  # The examples for that live in "every mistake a condition carries".
  describe "one family of checks, one message" do
    cases = {
      "a field that is a container" => [{ field: %w[id], operator: "=", value: "1" },
                                        :field_scalar],
      "a blank field" => [{ field: "  ", operator: "=", value: "1" }, :field_required],
      "an undeclared field" => [{ field: "secret", operator: "=", value: "1" }, :field_unknown],
      "an operator that is a container" => [
        { field: "id", operator: { a: "=" }, value: "1" }, :operator_scalar
      ],
      "a blank operator" => [{ field: "id", operator: " ", value: "1" }, :operator_required],
      "an operator outside the vocabulary" => [
        { field: "id", operator: "~", value: "1" }, :operator_invalid
      ],
      "a missing value key" => [{ field: "id", operator: "=" }, :value_required],
      # A list operator reads its value before deciding anything about it, and
      # a value that is not there is a value it has nothing to say about. The
      # missing key is therefore read first, or a condition naming +in+ and no
      # value at all passes the contract whole and reaches the engine with
      # nothing to build a membership test out of.
      "a missing value key on a list operator" => [
        { field: "id", operator: "in" }, :value_required
      ],
      "a value that is a container" => [
        { field: "id", operator: "=", value: { a: "1" } }, :value_scalar
      ],
      "a key the format does not define" => [
        { field: "id", operator: "=", value: "1", extra: "x" }, :unknown_key?
      ],
      "an entry that is not a condition at all" => ["id=1", :hash?],
    }

    cases.each do |description, (condition, key)|
      it "answers #{description} with that one message and nothing else" do
        expect(refusals(filters: [condition])).to eq(
          filters: { 0 => [message(key, fields: filterable)] },
        )
      end
    end
  end

  describe "every mistake a condition carries" do
    # A client told only that its field is undeclared corrects the field, sends
    # the request again, and learns the operator was wrong too — one round trip
    # per mistake, on a request it could have fixed in one. The order is the
    # fixed one: unknown key, then field, then operator, then value.
    it "answers a condition wrong on three axes with all three messages" do
      condition = { field: "  ", operator: "~" }

      expect(refusals(filters: [condition])).to eq(
        filters: {
          0 => [
            message(:field_required),
            message(:operator_invalid),
            message(:value_required),
          ],
        },
      )
    end

    # The invented key and the fault it looks like arrive together: a client
    # that misspelled +operator+ sent no operator. Reporting only the missing
    # operator sends it looking for a key it is certain it wrote, which is why
    # the keys are read first — and why reading them does not silence the rest.
    it "answers a stray key and an undeclared field with both messages" do
      condition = { field: "secret", operator: "=", value: "x", extra: "x" }

      expect(refusals(filters: [condition])).to eq(
        filters: { 0 => [message(:unknown_key?), message(:field_unknown, fields: filterable)] },
      )
    end

    # The value check reads the operator for its arity even when that operator
    # has just been refused. An operator outside the vocabulary is not a list
    # operator, so the array is judged on its own — and fixing either mistake
    # alone would still leave the request wrong.
    it "answers an invalid operator and a non-scalar value with both messages" do
      condition = { field: "id", operator: "~", value: %w[1 2] }

      expect(refusals(filters: [condition])).to eq(
        filters: { 0 => [message(:operator_invalid), message(:value_scalar)] },
      )
    end

    # Every family after the shape check reads keys, and an entry that is not
    # an object carries none. There is nothing further to say about a string
    # sitting where a condition was expected.
    it "answers an entry that is not an object with the shape message alone" do
      expect(refusals(filters: ["id=1"])).to eq(filters: { 0 => [message(:hash?)] })
    end

    # Attribution is the property that keeps a payload of malformed conditions
    # readable — not a limit on how many messages there are. Each condition's
    # messages stay under the index the client sent, whatever their number.
    it "keeps each condition's messages under its own index" do
      payload = {
        "0" => { field: "  ", operator: "~" },
        "3" => { field: "secret", operator: "=", value: "x" },
      }

      expect(refusals(filters: payload)).to eq(
        filters: {
          0 => [message(:field_required), message(:operator_invalid), message(:value_required)],
          3 => [message(:field_unknown, fields: filterable)],
        },
      )
    end
  end

  describe "the value's arity" do
    # Without this refusal the array reaches Arel, and because the relation is
    # lazy the refusal fires while the rows are enumerated — outside every
    # rescue, as a 500 answered to a client that sent a bad query string.
    it "refuses a non-scalar value for every operator that takes a single value" do
      refused = (Listable::OPERATORS - %w[in not_in]).map do |operator|
        refusals(filters: [{ field: "id", operator: operator, value: %w[1 2] }])
      end

      expect(refused).to all(eq(filters: { 0 => [message(:value_scalar)] }))
    end

    it "accepts a list of single values for a list operator" do
      accepted = %w[in not_in].map do |operator|
        refusals(filters: [{ field: "id", operator: operator, value: %w[1 2] }])
      end

      expect(accepted).to all(be_empty)
    end

    # A hand-written query string carries the list as one comma-separated
    # string, and the engine splits it.
    it "accepts a single value for a list operator" do
      expect(refusals(filters: [{ field: "id", operator: "in", value: "1,2" }])).to be_empty
    end

    it "refuses a list one of whose elements is a container" do
      condition = { field: "id", operator: "in", value: ["1", %w[2]] }

      expect(refusals(filters: [condition])).to eq(filters: { 0 => [message(:value_list)] })
    end

    it "refuses a map for a list operator" do
      condition = { field: "id", operator: "not_in", value: { a: "1" } }

      expect(refusals(filters: [condition])).to eq(filters: { 0 => [message(:value_list)] })
    end

    # A value the client sent is a value, whether or not it is empty; only a
    # missing key is a condition that forgot one.
    it "accepts an empty value and a nil value" do
      expect(refusals(filters: [{ field: "id", operator: "=", value: "" }])).to be_empty
      expect(refusals(filters: [{ field: "id", operator: "=", value: nil }])).to be_empty
    end
  end

  describe "what the contract deliberately leaves alone" do
    # Refusing this would make the gem's own operator vocabulary depend on the
    # host's schema, and would turn a client mistake the engine drops in
    # silence into a refusal the client cannot act on.
    it "passes an operator that suits no column of that field's type" do
      condition = { field: "quantity", operator: "ilike", value: "%3%" }

      expect(refusals(filters: [condition])).to be_empty
    end

    # A cast that fails drops its one condition inside the engine. Refusing it
    # here would turn a client mistake into a replayable server error.
    it "passes a value that cannot be cast" do
      expect(refusals(filters: [{ field: "quantity", operator: "=", value: "banana" }])).to be_empty
    end
  end

  describe "what the contract reads stripped" do
    # The normaliser strips the two of them, so validating the padded form
    # would either refuse a condition the engine reads perfectly well or accept
    # one it then drops in silence, answering an unfiltered listing to a client
    # that believes it filtered.
    it "validates a padded field and a padded operator as the normaliser reads them" do
      expect(refusals(filters: [{ field: " id ", operator: " = ", value: "1" }])).to be_empty
    end

    it "refuses a padded field the surface does not carry" do
      expect(refusals(filters: [{ field: " secret ", operator: "=", value: "1" }])).to eq(
        filters: { 0 => [message(:field_unknown, fields: filterable)] },
      )
    end
  end

  describe "the sort parameter" do
    it "refuses a sort that is not a string, once, on the sort parameter" do
      expect(refusals(sort: %w[name])).to eq(sort: [message(:sort_scalar)])
    end

    it "accepts the keys the sortable surface carries, in either direction" do
      expect(refusals(sort: "-name, id")).to be_empty
    end

    it "leaves a sort naming nothing at all alone" do
      expect(refusals(sort: " , - ,")).to be_empty
    end

    # The message enumerates the surface, so saying it once per undeclared key
    # would say the same thing three times.
    it "refuses several undeclared keys with exactly one failure" do
      expect(refusals(sort: "-secret,other,id")).to eq(
        sort: [message(:sort_unknown, fields: sortable)],
      )
    end

    # A client that sent both a payload and a sort has to be able to tell which
    # of the two it got wrong.
    it "never reports a sort failure under the filters parameter" do
      params = { filters: [{ field: "id", operator: "=", value: "1" }], sort: "secret" }

      expect(refusals(params)).to eq(sort: [message(:sort_unknown, fields: sortable)])
    end

    it "reports the two parameters apart when both are wrong" do
      params = { filters: "name=Gasket", sort: "secret" }

      expect(refusals(params)).to eq(
        filters: [message(:list?)],
        sort: [message(:sort_unknown, fields: sortable)],
      )
    end
  end
end
