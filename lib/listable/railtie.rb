# frozen_string_literal: true

module Listable
  # Hooks the gem into a Rails application's boot.
  #
  # The class is empty because its whole job is where it is defined, not what it
  # contains: it is required behind a +defined?(Rails::Railtie)+ check, so Rails
  # stays out of the gem's dependency graph and an Active Record host with no
  # Rails loads the gem unchanged. Being the gem's only Rails-aware object, it
  # is also the one place a boot-time hook belongs, which is why it exists
  # before it carries one.
  class Railtie < Rails::Railtie
  end
end
