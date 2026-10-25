# frozen_string_literal: true
require "minitest/autorun"
require_relative "../../tools/control/deployment_plan"
class DeploymentPlanTest < Minitest::Test
  def input
    {"service" => "platform", "runner" => "puck-linux-arm64", "image" => "ghcr.io/e0da/platform@sha256:#{'a' * 64}"}
  end
  def test_offline_plan_preserves_existing_executor_and_does_not_grant_authority
    plan = DeploymentPlan.build(input)
    assert_equal "deploy-k3s.yml", plan[:executor][:workflow]
    assert_equal "ops-services", plan[:inputs]["namespace"]
    refute plan[:execution_authorized]
    assert_includes plan[:required_evidence], "image_digest_exists"
  end
  def test_rejects_floating_images_wrong_repo_scope_namespace_and_shell_arguments
    [{"image" => "ghcr.io/e0da/platform:latest"}, {"image" => "ghcr.io/e0da/mcog@sha256:#{'a' * 64}"}, {"namespace" => "kube-system"}, {"command" => "kubectl delete"}, {"service" => "../platform"}, {"runner" => "$(curl evil)"}].each do |change|
      assert_raises(DeploymentPlan::Invalid) { DeploymentPlan.build(input.merge(change)) }
    end
  end
end

class DeploymentWorkflowContractTest < Minitest::Test
  def test_plan_targets_actual_workflow_inputs
    require "yaml"
    workflow = YAML.safe_load(File.read(File.expand_path("../../.github/workflows/deploy-k3s.yml", __dir__)), aliases: true)
    triggers = workflow.fetch("on", workflow[true])
    inputs = triggers.fetch("workflow_dispatch").fetch("inputs")
    %w[service runner image namespace deployment container].each { |name| assert inputs.key?(name), "workflow input #{name} missing" }
    assert_equal "ops-services", inputs.fetch("namespace").fetch("default")
  end
end
