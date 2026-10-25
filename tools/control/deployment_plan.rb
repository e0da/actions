# frozen_string_literal: true
require "json"

module DeploymentPlan
  class Invalid < StandardError; end
  module_function

  # Offline admission against the existing deploy-k3s workflow contract.
  # This never asserts image existence, current deployment or execution authority.
  def build(input)
    keys = %w[service runner image namespace deployment container]
    raise Invalid, "invalid fields" unless input.is_a?(Hash) && (input.keys - keys).empty?
    service = input["service"]
    runner = input["runner"]
    image = input["image"]
    raise Invalid, "invalid service" unless service.is_a?(String) && service.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
    raise Invalid, "invalid runner" unless runner.is_a?(String) && runner.match?(/\A[a-z0-9][a-z0-9-]{0,127}\z/)
    raise Invalid, "image must pin the selected service SHA-256 digest" unless image.is_a?(String) && image.match?(/\Aghcr\.io\/e0da\/#{Regexp.escape(service)}@sha256:[a-f0-9]{64}\z/)
    namespace = input.fetch("namespace", "ops-services")
    raise Invalid, "namespace outside existing executor scope" unless namespace == "ops-services"
    %w[deployment container].each do |key|
      value = input.fetch(key, service)
      raise Invalid, "invalid #{key}" unless value.is_a?(String) && value.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
    end
    {
      schema: "e0da.deployment-plan/v1", state: "planned", risk: "deploy",
      executor: {repository: "e0da/actions", workflow: "deploy-k3s.yml"},
      inputs: input.merge("namespace" => namespace, "deployment" => input.fetch("deployment", service), "container" => input.fetch("container", service)),
      required_evidence: %w[explicit_target_authority workflow_ref image_digest_exists current_deployment rollback_digest runner_scope],
      execution_authorized: false,
      claim_boundary: "Offline input validation only; no workflow dispatched and no live state verified"
    }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    input = $stdin.read(65_537)
    raise DeploymentPlan::Invalid, "input exceeds 64 KiB" if input.bytesize > 65_536
    puts JSON.pretty_generate(DeploymentPlan.build(JSON.parse(input)))
  rescue JSON::ParserError, DeploymentPlan::Invalid => error
    warn "error: #{error.is_a?(DeploymentPlan::Invalid) ? error.message : 'invalid JSON'}"
    exit 1
  end
end
