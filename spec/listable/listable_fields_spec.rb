# frozen_string_literal: true

RSpec.describe Listable, ".listable_fields" do
  it "reads back what the macro declared" do
    expect(Listable::Harness::Widget.listable_fields).to include("name", "quantity", "status")
  end

  it "reads back the declaration as strings" do
    expect(Listable::Harness::Gadget.listable_fields).to eq(%w[id name position])
  end

  # The most important claim in the gem: a model that declares nothing must
  # expose nothing. The class asserted on carries a real table with real
  # columns, so an empty answer is a decision and not an accident of the
  # harness.
  it "is empty on a model that declares nothing" do
    expect(Listable::Harness::SealedWidget.listable_fields).to eq([])
  end

  # Single-table inheritance must not lose the whitelist on the way down.
  it "is inherited by a subclass" do
    expect(Listable::Harness::SpecialWidget.listable_fields)
      .to eq(Listable::Harness::Widget.listable_fields)
  end

  # The macro is a convenience, not a ceiling: a surface that has to be built
  # at call time is expressed by overriding the class method.
  it "can be computed by a class method instead of declared" do
    expect(Listable::Harness::ComputedWidget.listable_fields).to eq(%w[name quantity owner])
  end
end
