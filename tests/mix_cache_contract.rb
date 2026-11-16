require 'yaml'
require 'minitest/autorun'

class MixCacheContract < Minitest::Test
  def setup
    @workflow = YAML.load_file('.github/workflows/ci-elixir.yml')
    @inputs = (@workflow['on'] || @workflow[true]).fetch('workflow_call').fetch('inputs')
    @steps = @workflow.fetch('jobs').fetch('mix').fetch('steps')
    @cache = @steps.find { |step| step['id'] == 'mix-cache' }
  end

  def test_root_callers_retain_paths_and_lock_file
    assert_equal "deps\n_build\n", @inputs.fetch('cache-paths').fetch('default')
    assert_equal 'mix.lock', @inputs.fetch('cache-lock-files').fetch('default')
    assert_equal '${{ inputs.cache-paths }}', @cache.fetch('with').fetch('path')
  end

  def test_cache_identity_is_scoped_to_compatible_project_and_platform
    cache = @cache.fetch('with')
    %w[runner.os runner.arch inputs.runner github.workflow inputs.otp-version inputs.elixir-version].each do |field|
      assert_includes cache.fetch('key'), "${{ #{field} }}"
      assert_includes cache.fetch('restore-keys'), "${{ #{field} }}"
    end
    assert_includes cache.fetch('key'), "${{ hashFiles(inputs.cache-lock-files) }}"
    assert_equal 1, cache.fetch('restore-keys').lines.length
    refute_includes cache.fetch('restore-keys'), '${{ runner.os }}-mix-'
  end

  def test_cache_does_not_replace_dependency_resolution_or_checks
    assert_equal "inputs.cache-mode == 'read-write'", @cache.fetch('if')
    %w[deps-command ci-command].each do |input|
      step = @steps.find { |entry| entry['run'] == "${{ inputs.#{input} }}" }
      refute_nil step
      refute step.key?('if')
    end
  end
end
