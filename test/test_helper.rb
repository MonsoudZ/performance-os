ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

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
