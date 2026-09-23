# frozen_string_literal: true

RSpec.describe Listable::Conditions do
  # Normalises a payload and reports the conditions it yields.
  #
  # Every example goes through the one reading entry the object offers, which
  # is the seam the suite is allowed to touch: no internal of the normaliser is
  # reached, and what is asserted is the list a caller would hand the engine.
  #
  # ==== Parameters
  #
  # * +payload+ - the raw filters payload
  #
  # ==== Returns
  #
  # The normalised list of conditions.
  def normalised(payload)
    described_class.new(payload).to_a
  end

  describe "the two accepted shapes" do
    it "reads an array payload as its conditions, in order" do
      payload = [
        { "field" => "quantity", "operator" => ">=", "value" => "3" },
        { "field" => "name", "operator" => "ilike", "value" => "%ask%" },
      ]
      expected = [
        { field: "quantity", operator: ">=", value: "3" },
        { field: "name", operator: "ilike", value: "%ask%" },
      ]

      expect(normalised(payload)).to eq(expected)
    end

    it "reads a hash whose keys are all numeric strings as its values, in order" do
      payload = {
        "0" => { "field" => "quantity", "operator" => ">=", "value" => "3" },
        "1" => { "field" => "quantity", "operator" => "<=", "value" => "7" },
      }
      expected = [
        { field: "quantity", operator: ">=", value: "3" },
        { field: "quantity", operator: "<=", value: "7" },
      ]

      expect(normalised(payload)).to eq(expected)
    end

    # A client that drops one condition out of a form leaves a hole behind
    # rather than renumbering what it kept.
    it "accepts indices that are not contiguous" do
      payload = {
        "0" => { "field" => "quantity", "operator" => "=", "value" => "3" },
        "7" => { "field" => "name", "operator" => "=", "value" => "Gasket" },
      }

      expect(normalised(payload).map { |condition| condition[:value] }).to eq(%w[3 Gasket])
    end

    # The index is the position, which is what makes the indexed hash and the
    # array mean the same list rather than merely carry the same conditions.
    it "orders the entries of a hash by the index the client sent" do
      payload = {
        "1" => { "field" => "name", "operator" => "=", "value" => "second" },
        "0" => { "field" => "name", "operator" => "=", "value" => "first" },
      }

      expect(normalised(payload).map { |condition| condition[:value] }).to eq(%w[first second])
    end

    it "reads a condition written with symbol keys as readily as one with string keys" do
      payload = [{ field: "quantity", operator: "=", value: "7" }]

      expect(normalised(payload)).to eq([{ field: "quantity", operator: "=", value: "7" }])
    end
  end

  describe "a payload that is not a positional list" do
    # Keeping the numeric keys and dropping the odd one out would narrow a
    # listing by some of what the client sent and report nothing about the
    # rest. The whole payload is in a format the engine does not speak.
    it "normalises a hash carrying a single non-numeric key to an empty list" do
      payload = {
        "0" => { "field" => "quantity", "operator" => "=", "value" => "3" },
        "name" => { "field" => "name", "operator" => "=", "value" => "Gasket" },
      }

      expect(normalised(payload)).to eq([])
    end

    # The map keyed by field name is the format this one replaces: it cannot
    # express two conditions on the same field, which is the whole point of
    # the positional shape.
    it "normalises a map keyed by field name to an empty list" do
      payload = {
        "quantity" => { "operator" => ">=", "value" => "3" },
        "name" => { "operator" => "ilike", "value" => "%ask%" },
      }

      expect(normalised(payload)).to eq([])
    end

    it "normalises a key that only looks numeric to an empty list" do
      payload = { "0x" => { "field" => "quantity", "operator" => "=", "value" => "3" } }

      expect(normalised(payload)).to eq([])
    end

    it "normalises any other input type to an empty list" do
      expect(normalised(nil)).to eq([])
      expect(normalised("quantity")).to eq([])
      expect(normalised(7)).to eq([])
      expect(normalised(Object.new)).to eq([])
    end
  end

  describe "one condition" do
    # The contract validates the field and the operator stripped, so a padded
    # operator passes validation. The engine strips nothing and would match a
    # padded operator against no operator function, drop the condition in
    # silence, and hand back a listing wider than the client asked for.
    it "strips the field and the operator" do
      payload = [{ "field" => "  quantity  ", "operator" => " >= ", "value" => " 3 " }]

      expect(normalised(payload)).to eq([{ field: "quantity", operator: ">=", value: " 3 " }])
    end

    it "drops a condition that is not an object" do
      payload = ["quantity", nil, 7, { "field" => "name", "operator" => "=", "value" => "Gasket" }]

      expect(normalised(payload)).to eq([{ field: "name", operator: "=", value: "Gasket" }])
    end

    it "drops a condition naming a blank field" do
      payload = [
        { "field" => "   ", "operator" => "=", "value" => "3" },
        { "operator" => "=", "value" => "3" },
      ]

      expect(normalised(payload)).to eq([])
    end

    it "drops a condition naming a blank operator" do
      payload = [
        { "field" => "quantity", "operator" => "  ", "value" => "3" },
        { "field" => "quantity", "value" => "3" },
      ]

      expect(normalised(payload)).to eq([])
    end

    # The condition is rebuilt from the three keys the format defines rather
    # than copied and pruned, so nothing else reaches the engine.
    it "drops the keys beyond field, operator and value" do
      payload = [
        { "field" => "quantity", "operator" => "=", "value" => "3", "table" => "widgets" },
      ]

      expect(normalised(payload)).to eq([{ field: "quantity", operator: "=", value: "3" }])
    end

    # A value set to nil or to the empty string is a value the client sent.
    it "keeps a condition whose value key carries an empty or null value" do
      payload = [
        { "field" => "name", "operator" => "=", "value" => "" },
        { "field" => "name", "operator" => "=", "value" => nil },
      ]
      expected = [
        { field: "name", operator: "=", value: "" },
        { field: "name", operator: "=", value: nil },
      ]

      expect(normalised(payload)).to eq(expected)
    end

    # A missing value key is not the same thing as an empty value, and the
    # contract tells the two apart.
    it "carries no value key when the condition had none" do
      payload = [{ "field" => "released_on", "operator" => "is" }]

      expect(normalised(payload)).to eq([{ field: "released_on", operator: "is" }])
    end

    it "preserves duplicate conditions, in arrival order" do
      condition = { "field" => "quantity", "operator" => "=", "value" => "3" }
      payload = [condition, { "field" => "name", "operator" => "=", "value" => "x" }, condition]

      expect(normalised(payload).map { |normal| normal[:field] })
        .to eq(%w[quantity name quantity])
    end
  end

  describe "the numeric-index pattern" do
    # The contract reads this very constant to decide whether a payload is a
    # positional list. Widening either side alone would let the contract accept
    # a payload this normaliser then empties, answering a success that filtered
    # nothing.
    it "is exposed as a pattern the validation contract can read" do
      expect(described_class::INDEX).to be_a(Regexp)
    end

    it "matches an index and nothing else" do
      expect(described_class::INDEX).to match("0")
      expect(described_class::INDEX).to match("12")
      expect(described_class::INDEX).not_to match("name")
      expect(described_class::INDEX).not_to match("1x")
      expect(described_class::INDEX).not_to match("")
    end

    # Anchored with \A and \z rather than ^ and $, which match around a
    # newline and would read a key smuggling one as an index.
    it "matches no key carrying a newline" do
      expect(described_class::INDEX).not_to match("0\nname")
    end
  end

  describe "the list the filtering engine reads" do
    let(:model) { Listable::Harness::Widget }

    before do
      model.create!(name: "Spindle", quantity: 3)
      model.create!(name: "Gasket", quantity: 7)
      model.create!(name: "bolt", quantity: 11)
    end

    # The relation is enumerated on purpose: the claim is that the engine reads
    # what the normaliser writes, and only the rows a real query answers can
    # say so. An assertion on the shape of the normalised list would pass on an
    # output the engine cannot read at all.
    it "narrows a real relation with the conditions it normalised" do
      payload = {
        "0" => { "field" => "quantity", "operator" => ">=", "value" => "3" },
        "1" => { "field" => "quantity", "operator" => "<=", "value" => "7" },
      }

      expect(model.filtering(normalised(payload)).map(&:name))
        .to contain_exactly("Spindle", "Gasket")
    end

    # The two halves of the division of labour, measured against the same
    # relation: the engine drops a padded operator because stripping is not its
    # job, and normalisation is what keeps that from ever happening.
    it "hands the engine an operator it can match, out of a padded one" do
      payload = [{ "field" => "quantity", "operator" => " = ", "value" => "7" }]

      expect(model.filtering(normalised(payload)).map(&:name)).to eq(["Gasket"])
      expect(model.filtering(payload).map(&:name))
        .to contain_exactly("Spindle", "Gasket", "bolt")
    end

    it "leaves the relation whole when the payload is not a positional list" do
      payload = { "quantity" => { "operator" => "=", "value" => "7" } }

      expect(model.filtering(normalised(payload)).map(&:name))
        .to contain_exactly("Spindle", "Gasket", "bolt")
    end
  end
end
