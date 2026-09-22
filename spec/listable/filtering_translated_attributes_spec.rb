# frozen_string_literal: true

RSpec.describe Listable, ".filtering", :translated do
  let(:model) { Listable::Harness::Document }

  let!(:spindle) do
    model.create!.tap do |document|
      Listable::Harness::Translations.with_locale(:en) { document.update!(name: "Spindle") }
      Listable::Harness::Translations.with_locale(:ja) { document.update!(name: "スピンドル") }
    end
  end

  let!(:gasket) do
    model.create!.tap do |document|
      Listable::Harness::Translations.with_locale(:en) { document.update!(name: "Gasket") }
    end
  end

  let!(:untranslated) { model.create! }

  # Narrows the documents in a given locale and reports the rows it answers.
  #
  # The locale is set around the whole call because the expression a filter
  # compares is decided when the predicate is built, and it is the reader's
  # locale that decides it.
  #
  # ==== Parameters
  #
  # * +locale+ - the locale to read the attribute in
  # * +operator+ - the operator the condition names
  # * +value+ - the value the condition carries
  #
  # ==== Returns
  #
  # The ids of the rows the relation answers.
  def ids_in(locale, operator, value)
    Listable::Harness::Translations.with_locale(locale) do
      model.filtering([{ field: "name", operator: operator, value: value }]).map(&:id)
    end
  end

  it "matches the value of the current locale" do
    expect(ids_in(:en, "=", "Spindle")).to eq([spindle.id])
  end

  # The column holds a JSON document keyed by locale. Comparing the column
  # rather than the locale extraction compares that whole document, and a
  # filter on a translated name then matches nothing a client would ever type.
  it "compares the locale's value and not the whole document" do
    expect(ids_in(:en, "=", "スピンドル")).to eq([])
  end

  it "reads the current locale when the row carries one" do
    expect(ids_in(:ja, "=", "スピンドル")).to eq([spindle.id])
  end

  # The chain is the backend's own, so a row translated only in the fallback
  # locale is found by a client reading in the locale that falls back to it —
  # exactly as the reader would have shown it that value.
  it "falls back down the backend's chain" do
    expect(ids_in(:ja, "=", "Gasket")).to eq([gasket.id])
  end

  it "does not let a fallback shadow the value of the current locale" do
    expect(ids_in(:ja, "=", "Spindle")).to eq([])
  end

  # A chain of one locale emits a bare extraction rather than a COALESCE, and
  # it has to answer the same rows as the folded form does.
  it "matches on a single-locale chain" do
    expect(ids_in(:en, "=", "Gasket")).to eq([gasket.id])
  end

  # The extraction yields text by construction, so a translated attribute is
  # always textual and every pattern operator applies to it — including on the
  # folded chain, where the compared expression is a function call rather than
  # a column.
  it "accepts a case-insensitive pattern on the current locale" do
    expect(ids_in(:en, "ilike", "%PIND%")).to eq([spindle.id])
  end

  it "accepts a case-sensitive pattern on a folded chain" do
    expect(ids_in(:ja, "like", "%Gask%")).to eq([gasket.id])
  end

  it "tests a translated attribute for the absence of a value" do
    expect(ids_in(:en, "is", "null")).to eq([untranslated.id])
  end

  it "tests a list of translated values" do
    expect(ids_in(:en, "in", "Spindle, Gasket")).to contain_exactly(spindle.id, gasket.id)
  end
end
