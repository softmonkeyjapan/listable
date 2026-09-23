# frozen_string_literal: true

module Listable
  # Hooks the gem into a Rails application's boot.
  #
  # It is required behind a +defined?(Rails::Railtie)+ check, so Rails stays out
  # of the gem's dependency graph and an Active Record host with no Rails loads
  # the gem unchanged. Being the gem's only Rails-aware object, it is the one
  # place a boot-time hook belongs.
  class Railtie < Rails::Railtie
    # Puts the gem's locale files on the application's i18n load path.
    #
    # The contract already stores its messages into the i18n backend when it is
    # first used, so a host that never boots Rails reads real messages without
    # this initializer. What the load path buys is survival: an application
    # reloads its translations — at boot, and again on every code reload in
    # development — and a reload throws away everything that was stored rather
    # than loaded from a path. Without this line the gem's messages are there
    # until the first reload and are +translation missing+ afterwards, which is
    # a failure a host meets in development and never in its test suite.
    #
    # The files are appended rather than prepended, so a host that loads a file
    # of its own afterwards overrides the single message it names — i18n merges
    # what comes later over what came before — and keeps the fourteen others.
    initializer "listable.i18n" do |app|
      app.config.i18n.load_path += Contract::MESSAGE_PATHS
    end
  end
end
