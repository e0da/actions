# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class PrQualityConcurrencyTest < Minitest::Test
  def setup
    @job = YAML.load_file(".github/workflows/pr-quality.yml").fetch("jobs").fetch("pr-quality")
  end

  def group(repo:, pr:, run:)
    @job.fetch("concurrency").fetch("group").gsub(/\$\{\{\s*(.*?)\s*\}\}/) do
      case Regexp.last_match(1)
      when "github.repository" then repo
      when "github.event.pull_request.number" then pr.to_s
      when "github.event.pull_request.number || github.run_id" then (pr || run).to_s
      else flunk "unqualified concurrency expression: #{Regexp.last_match(1)}"
      end
    end
  end

  def cancellation(pr:)
    policy = @job.fetch("concurrency").fetch("cancel-in-progress")
    case policy
    when true, false then policy
    when "${{ github.event.pull_request.number != '' }}" then !pr.nil? && pr != ""
    else flunk "unqualified cancellation policy: #{policy}"
    end
  end

  def test_latest_metadata_event_replaces_an_older_event
    assert cancellation(pr: 327)
    assert_equal group(repo: "e0da/stack", pr: 327, run: 101), group(repo: "e0da/stack", pr: 327, run: 102)
  end

  def test_distinct_prs_and_repositories_keep_independent_checks
    original = group(repo: "e0da/stack", pr: 327, run: 101)
    refute_equal original, group(repo: "e0da/stack", pr: 331, run: 102)
    refute_equal original, group(repo: "e0da/actions", pr: 327, run: 102)
  end

  def test_non_pr_runs_remain_independent
    refute cancellation(pr: nil)
    refute_equal group(repo: "e0da/stack", pr: nil, run: 101), group(repo: "e0da/stack", pr: nil, run: 102)
  end

  def test_coalesced_job_remains_read_only
    assert_equal({ "contents" => "read", "pull-requests" => "read" }, @job.fetch("permissions"))
    assert_equal "${{ github.token }}", @job.fetch("steps").first.fetch("env").fetch("GH_TOKEN")
  end
end
