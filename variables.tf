variable "subscription_id" {
  description = "Subscription to deploy the lab into. Use a test subscription you own."
  type        = string
}

variable "location" {
  description = "Azure region. Must be a region where Azure SRE Agent is available."
  type        = string
  default     = "swedencentral"
}

variable "name" {
  description = "Short name used in every resource name."
  type        = string
  default     = "srepoc"
}

variable "vm_size" {
  description = "Size of the two lab VMs. Must support Premium SSD (the IOPS scenario uses a P1 disk)."
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "agent_mode" {
  description = "ReadOnly (no write actions at all), Review (proposes write actions and waits for approval) or Autonomous."
  type        = string
  default     = "Review"

  validation {
    condition     = contains(["ReadOnly", "Review", "Autonomous"], var.agent_mode)
    error_message = "agent_mode must be ReadOnly, Review or Autonomous."
  }
}

variable "agent_model" {
  description = <<-EOT
    Model name, or "Automatic" to let the agent pick per task. Values offered in Sweden Central on 2026-11-02
    (supportedAgentModels API): MicrosoftFoundry: Automatic, gpt-5.4, gpt-5.6-terra, gpt-6-luna, gpt-6-sol,
    gpt-6.1-sol. Anthropic: Automatic, claude-sonnet-4-5, claude-sonnet-4-6, claude-sonnet-5-5,
    claude-opus-4-5, claude-opus-4-6, claude-opus-4-7, claude-opus-4-8, claude-opus-5, claude-opus-5-5.
  EOT
  type        = string
  default     = "Automatic"
}

variable "agent_model_provider" {
  description = "Model provider: MicrosoftFoundry (Azure OpenAI GPT models, inside the EU Data Boundary) or Anthropic (Claude, outside the EU Data Boundary)."
  type        = string
  default     = "MicrosoftFoundry"

  validation {
    condition     = contains(["MicrosoftFoundry", "Anthropic"], var.agent_model_provider)
    error_message = "agent_model_provider must be MicrosoftFoundry or Anthropic."
  }
}

variable "agent_network_mode" {
  description = "Agent sandbox egress: AzureVNet (through snet-agent, your NSG/routes/DNS apply), Limited (Microsoft-hosted, allow-list only) or Unrestricted."
  type        = string
  default     = "AzureVNet"

  validation {
    condition     = contains(["AzureVNet", "Limited", "Unrestricted"], var.agent_network_mode)
    error_message = "agent_network_mode must be AzureVNet, Limited or Unrestricted."
  }
}

variable "deploy_sre_agent" {
  description = "Deploy the Azure SRE Agent. Set to false between sessions to stop its always-on cost."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Faults. All false = healthy baseline. Turn on one at a time:
#   terraform apply -var fault_nsg_blocks_acr=true
# Running apply again without the -var turns it back off.
# ---------------------------------------------------------------------------

variable "fault_nsg_blocks_acr" {
  description = "NSG on the private endpoint subnet denies HTTPS from the web app subnet: image pull fails."
  type        = bool
  default     = false
}

variable "fault_acr_pull_role_missing" {
  description = "The web app identity loses AcrPull on the registry: image pull is unauthorized."
  type        = bool
  default     = false
}

variable "fault_private_dns_unlinked" {
  description = "The privatelink.azurecr.io zone is unlinked from the VNet: the registry name resolves to its public IP."
  type        = bool
  default     = false
}

variable "fault_route_blackhole" {
  description = "Route table sends 0.0.0.0/0 from the VM subnet to a next hop that doesn't exist."
  type        = bool
  default     = false
}

variable "fault_smtp_blocked" {
  description = "NSG denies outbound TCP 587 (SMTP submission) from the VM subnet. Port 25 is blocked by Azure itself on most subscription types."
  type        = bool
  default     = false
}

variable "fault_rbac_wrong_scope" {
  description = "The ops identity gets Contributor on another resource group instead of the lab one: writes to the lab are denied."
  type        = bool
  default     = false
}

variable "address_space" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Lab VNet range (a /16). Subnets are carved from it; pick a range that does not overlap your networks."
  validation {
    condition     = can(cidrhost(var.address_space, 0)) && tonumber(split("/", var.address_space)[1]) == 16
    error_message = "address_space must be a valid /16, e.g. 10.0.0.0/16."
  }
}
