# frozen_string_literal: true

RSpec.describe Listable, ".sorting", :translated do
  let(:model) { Listable::Harness::Document }

  let!(:yankee) do
    model.create!.tap do |document|
      Listable::Harness::Translations.with_locale(:en) { document.update!(name: "Alpha") }
      Listable::Harness::Translations.with_locale(:ja) { document.update!(name: "Yankee") }
    end
  end

  let!(:bravo) do
    model.create!.tap do |document|
      Listable::Harness::Translations.with_locale(:en) { document.update!(name: "Zulu") }
      Listable::Harness::Translations.with_locale(:ja) { document.update!(name: "Bravo") }
    end
  end

  let!(:mike) do
    model.create!.tap do |document|
      Listable::Harness::Translations.with_locale(:en) { document.update!(name: "Mike") }
    end
  end

  # Orders the documents in a given locale and reports the rows it answers.
  #
  # The locale is set around the whole call because the expression the order
  # reads is decided when the ordering is built, and it is the reader's locale
  # that decides it.
  #
  # ==== Parameters
  #
  # * +locale+ - the locale to read the attribute in
  # * +sort+ - the sort parameter as a client would send it
  #
  # ==== Returns
  #
  # The ids of the rows the relation answers, in order.
  def ids_in(locale, sort)
    Listable::Harness::Translations.with_locale(locale) do
      model.sorting(sort).map(&:id)
    end
  end

  it "orders on the value of the current locale" do
    expect(ids_in(:en, "name")).to eq([yankee.id, mike.id, bravo.id])
  end

  # The column holds a JSON document keyed by locale. Ordering on the column
  # would sort the rows by that serialised object — which here puts the
  # single-pair document first and answers an order matching nothing a client
  # can read on screen.
  it "orders on the locale extraction and not on the whole document" do
    expect(ids_in(:en, "name")).not_to eq([mike.id, yankee.id, bravo.id])
  end

  # The chain is the backend's own, so a row translated only in the fallback
  # locale takes the rank its fallback value earns instead of the rank a null
  # would give it — exactly where the reader would show it.
  it "orders down the backend's fallback chain" do
    expect(ids_in(:ja, "name")).to eq([bravo.id, mike.id, yankee.id])
  end

  it "reverses the same extraction on the descending marker" do
    expect(ids_in(:ja, "-name")).to eq([yankee.id, mike.id, bravo.id])
  end
end
