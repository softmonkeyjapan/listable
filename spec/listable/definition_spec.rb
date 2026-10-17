# frozen_string_literal: true

RSpec.describe Listable::Definition do
  let(:model) { Listable::Harness::Widget }

  # A filter serving +heavy+, a field that is no column: the widgets carrying
  # more than a quantity, and the refusal of anything but +>+ and a number.
  let(:heavy_filter) do
    Class.new do
      # Narrows the widgets to those carrying more than the value.
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
        relation.where("quantity > ?", value.to_i)
      end

      # Names what is wrong with a condition on +heavy+.
      #
      # ==== Parameters
      #
      # * +operator+ - the operator the condition named
      # * +_value+ - the value the condition carried
      #
      # ==== Returns
      #
      # A message key, or +nil+.
      def self.refusal(operator, _value)
        :heavy_operator unless operator == ">"
      end
    end
  end

  # A sort serving +weight+, a key that is no column: the quantity, reversed,
  # so that an order it produced cannot be mistaken for one on the column.
  let(:weight_sort) do
    Class.new do
      # Orders on the opposite of the quantity.
      #
      # ==== Parameters
      #
      # * +relation+ - the relation being ordered
      # * +descending+ - whether the client asked for the descending order
      #
      # ==== Returns
      #
      # The Arel ordering node.
      def self.ordering(relation, descending)
        expression = relation.arel_table[:quantity]

        descending ? expression.asc : expression.desc
      end
    end
  end

  # The listing under test, declared once.
  #
  # ==== Returns
  #
  # A definition of the widget listing carrying one custom filter and one
  # custom sort.
  def definition
    described_class.new(model, filters: { "heavy" => heavy_filter }, sorts: { weight: weight_sort })
  end

  before do
    model.create!(name: "Spindle", quantity: 3, created_at: Time.utc(2026, 1, 15))
    model.create!(name: "Gasket", quantity: 7, created_at: Time.utc(2026, 2, 10))
    model.create!(name: "bolt", quantity: 11, created_at: Time.utc(2026, 3, 5))
  end

  describe "#contract" do
    it "accepts a filter on the model's surface and on a custom filter's field" do
      params = { filters: [{ field: "name", operator: "=", value: "bolt" },
                           { field: "heavy", operator: ">", value: "5" }] }

      expect(definition.contract.call(params).errors.to_h).to be_empty
    end

    it "asks the custom filter its refusal" do
      messages = { heavy_operator: "heavy takes >" }
      I18n.backend.store_translations(I18n.locale, listable: { errors: messages })
      params = { filters: [{ field: "heavy", operator: "=", value: "5" }] }

      expect(definition.contract.call(params).errors.to_h)
        .to eq(filters: { "0" => ["heavy takes >"] })
    ensure
      I18n.backend.store_translations(I18n.locale, listable: { errors: { heavy_operator: nil } })
    end

    # The custom filter's field is no column and no custom sort serves it, so
    # there is nothing to order by: the two surfaces diverge here.
    it "refuses an order on a custom filter's field" do
      expect(definition.contract.call(sort: "heavy").errors.to_h).to have_key(:sort)
    end

    it "accepts an order on a custom sort's key, which it refuses as a filter" do
      filters = [{ field: "weight", operator: "=", value: "1" }]
      result = definition.contract.call(sort: "-weight", filters: filters)

      expect(result.errors.to_h.keys).to eq([:filters])
    end
  end

  describe "#apply" do
    it "narrows through the custom filter and orders through the custom sort" do
      filters = { "0" => { "field" => "heavy", "operator" => ">", "value" => "5" } }

      listing = definition.apply(model.all, filters: filters, sort: "weight")

      expect(listing.map(&:name)).to eq(%w[bolt Gasket])
    end

    it "narrows on a declared column like filtering does" do
      filters = [{ field: "name", operator: "=", value: "Gasket" }]

      expect(definition.apply(model.all, filters: filters, sort: nil).map(&:name)).to eq(%w[Gasket])
    end

    it "narrows the relation it is handed and never widens it" do
      scope = model.where(name: %w[Spindle Gasket])

      listing = definition.apply(scope, filters: nil, sort: "name")

      expect(listing.map(&:name)).to eq(%w[Gasket Spindle])
    end
  end
end
