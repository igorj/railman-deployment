require 'test_helper'

class RailmanDeploymentTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::RailmanDeployment::VERSION
  end
end
