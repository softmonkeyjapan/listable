# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

# The two gates a commit must pass, in the order a failure is cheapest to read.
task default: %i[spec rubocop]
