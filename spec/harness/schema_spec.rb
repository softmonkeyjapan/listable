# frozen_string_literal: true

RSpec.describe Listable::Harness::Widget do
  # The casting rules read a column's type off the schema, so the suite is only
  # worth its assertions if every type it claims to cover is really the type
  # PostgreSQL gave the column back.
  let(:expected_types) do
    {
      "id" => :integer,
      "name" => :string,
      "description" => :text,
      "quantity" => :integer,
      "reference" => :integer,
      "price" => :decimal,
      "ratio" => :float,
      "active" => :boolean,
      "released_on" => :date,
      "published_at" => :datetime,
      "status" => :string,
      "created_at" => :datetime,
    }
  end

  it "resolves each declared column to its expected type" do
    expect(described_class.columns_hash.transform_values(&:type)).to eq(expected_types)
  end

  # Active Record maps bigint and integer onto the same +:integer+ type, so the
  # map above stays green if +reference+ is narrowed to a plain integer and the
  # bigint the casting rules have to cover disappears with no test to notice.
  # The database type is the one that tells the two apart, which is why this
  # assertion is not the redundancy it reads as.
  it "backs the wide integer column with a database bigint" do
    expect(described_class.columns_hash["reference"].sql_type).to eq("bigint")
    expect(described_class.columns_hash["quantity"].sql_type).to eq("integer")
  end

  # An enum is an attribute-level decoration. Reading textuality off the
  # attribute would make this column non-textual and silently deny it the
  # pattern operators, which is why the schema type is asserted next to the
  # enum that could be mistaken for it.
  it "keeps the enum-backed column a string" do
    expect(described_class.statuses.keys).to contain_exactly("draft", "published", "archived")
    expect(described_class.columns_hash["status"].type).to eq(:string)
  end

  it "stores a record created through plain Active Record" do
    widget = described_class.create!(name: "spindle", quantity: 3, status: "draft")

    expect(described_class.find(widget.id).name).to eq("spindle")
  end
end

RSpec.describe Listable::Harness::Gadget do
  it "resolves each declared column to its expected type" do
    expect(described_class.columns_hash.transform_values(&:type)).to eq(
      "id" => :integer,
      "name" => :string,
      "position" => :integer,
    )
  end

  # The default order falls back to the primary key alone when the table has no
  # creation timestamp. A +created_at+ appearing here would make that fallback
  # untestable while every example kept passing.
  it "carries no creation timestamp" do
    expect(described_class.column_names).not_to include("created_at")
  end
end

RSpec.describe Listable::Harness::Document do
  it "resolves each declared column to its expected type" do
    expect(described_class.columns_hash.transform_values(&:type)).to eq(
      "id" => :integer,
      "name" => :jsonb,
      "created_at" => :datetime,
    )
  end
end
