# frozen_string_literal: true

RSpec.describe Listable, ".filtering" do
  let(:model) { Listable::Harness::Widget }

  # A filter that narrows on a column other than the field it claims.
  #
  # The mismatch is the assertion: a filter that reproduced what the column of
  # the same name would have done could not tell the two apart, and the claim
  # under test is precisely that the lookup wins over the column.
  let(:by_quantity) do
    Class.new do
      # Narrows the relation on a quantity, whatever field claimed this filter.
      #
      # ==== Parameters
      #
      # * +relation+ - the relation as the previous conditions left it
      # * +_operator+ - the operator the condition named
      # * +value+ - the value the condition carried
      #
      # ==== Returns
      #
      # The narrowed relation.
      def self.apply(relation, _operator, value)
        relation.where(quantity: value)
      end
    end
  end

  # A filter that records what it was handed and narrows nothing.
  let(:recorder) do
    Class.new do
      # The calls this filter has received, oldest first.
      #
      # ==== Returns
      #
      # An array of operator and value pairs.
      def self.calls
        @calls ||= []
      end

      # Records the call and hands the relation back untouched.
      #
      # ==== Parameters
      #
      # * +relation+ - the relation as the previous conditions left it
      # * +operator+ - the operator the condition named
      # * +value+ - the value the condition carried
      #
      # ==== Returns
      #
      # The relation, unchanged.
      def self.apply(relation, operator, value)
        calls << [relation, operator, value]
        relation
      end
    end
  end

  # A filter that fails the way a host's own code would.
  let(:broken) do
    Class.new do
      # Fails, so that the absence of a rescue around a custom filter shows.
      #
      # ==== Parameters
      #
      # * +_relation+ - the relation as the previous conditions left it
      # * +_operator+ - the operator the condition named
      # * +_value+ - the value the condition carried
      #
      # ==== Returns
      #
      # Nothing: it always raises.
      def self.apply(_relation, _operator, _value)
        raise "the host's filter failed"
      end
    end
  end

  before do
    model.create!(name: "Spindle", quantity: 3)
    model.create!(name: "Gasket", quantity: 7)
  end

  # The lookup runs before the field is treated as a column, so a filter takes
  # the field even when a column of that name exists and would have answered.
  it "claims a field ahead of the column of the same name" do
    conditions = [{ field: "name", operator: "=", value: "7" }]

    expect(model.filtering(conditions, "name" => by_quantity).map(&:name)).to eq(["Gasket"])
  end

  # The same lookup runs before the declared surface is consulted, which is how
  # a listing filters on an association or a computed perimeter without that
  # name ever entering the model's whitelist.
  it "claims a field the model does not declare" do
    conditions = [{ field: "owner", operator: "=", value: "7" }]

    expect(model.filtering(conditions, "owner" => by_quantity).map(&:name)).to eq(["Gasket"])
  end

  it "is found under a symbol key as readily as under a string one" do
    conditions = [{ field: "owner", operator: "=", value: "3" }]

    expect(model.filtering(conditions, owner: by_quantity).map(&:name)).to eq(["Spindle"])
  end

  it "receives the relation, the operator and the value" do
    conditions = [{ field: "owner", operator: ">=", value: "3" }]

    model.filtering(conditions, "owner" => recorder).to_a

    expect(recorder.calls.length).to eq(1)
    expect(recorder.calls.first[0]).to be_a(ActiveRecord::Relation)
    expect(recorder.calls.first[1..]).to eq([">=", "3"])
  end

  it "hands its answer on to the conditions that follow it" do
    conditions = [
      { field: "owner", operator: "=", value: "7" },
      { field: "name", operator: "ilike", value: "%ask%" },
    ]

    expect(model.filtering(conditions, "owner" => by_quantity).map(&:name)).to eq(["Gasket"])
  end

  # The gem wraps no rescue around a custom filter: an error raised inside one
  # belongs to the host that wrote it, and swallowing it here would turn a bug
  # in the host's code into a listing that quietly stopped filtering.
  it "lets an error raised inside it propagate" do
    conditions = [{ field: "name", operator: "=", value: "Gasket" }]

    expect { model.filtering(conditions, "name" => broken) }
      .to raise_error(RuntimeError, "the host's filter failed")
  end
end
