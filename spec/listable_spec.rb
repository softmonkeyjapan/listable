# frozen_string_literal: true

RSpec.describe Listable do
  it "defines the gem's namespace" do
    expect(described_class).to be_a(Module)
  end

  it "carries a version constant" do
    expect(Listable::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe "OPERATORS" do
    it "is exposed as a public constant carrying eleven operators" do
      expect(Listable::OPERATORS).to contain_exactly(
        "=", "!=", ">", ">=", "<", "<=", "in", "not_in", "like", "ilike", "is"
      )
    end

    it "is frozen, so that a host reading it cannot widen it" do
      expect(Listable::OPERATORS).to be_frozen
    end
  end

  describe "the railtie" do
    # Rails is not in the suite's bundle, which is what makes this assertion a
    # measurement rather than a tautology: the gem is loaded here exactly as an
    # Active Record host with no Rails loads it.
    it "is absent when Rails is absent" do
      expect(defined?(Rails::Railtie)).to be_nil
      expect(defined?(Listable::Railtie)).to be_nil
    end

    # The other half of the same claim has to run in a child process. Defining
    # +Rails::Railtie+ in the suite's own process would leave a root constant
    # and a loaded +Listable::Railtie+ standing for every example that runs
    # afterwards, and the absence example above — which can run after this one,
    # the order being random — would then be asserting against the residue of
    # this one instead of against a Rails-free load.
    it "subclasses Rails::Railtie when Rails is present" do
      script = <<~RUBY
        module Rails
          class Railtie; end
        end

        require "listable"

        print Listable::Railtie.superclass
      RUBY

      output = IO.popen([RbConfig.ruby, "-I", lib_path, "-e", script], err: %i[child out], &:read)

      expect(Process.last_status).to be_success
      expect(output).to eq("Rails::Railtie")
    end
  end

  # The child process gets the gem's load path explicitly; it inherits the
  # bundle from the environment the suite already runs under.
  #
  # ==== Returns
  #
  # The absolute path of the gem's +lib+ directory.
  def lib_path
    File.expand_path("../lib", __dir__)
  end
end
