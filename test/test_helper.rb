ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "test_helpers/session_test_helper"

# Outbound HTTP must be stubbed in tests; a stray real request fails loudly.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Evaluator pipelines now run in background jobs; tests drive them explicitly
    # with perform_enqueued_jobs / assert_enqueued_with.
    include ActiveJob::TestHelper

    # Add more helper methods to be used by all tests here...
  end
end
