# AGENTS.md

Instructions for any coding agent (Codex, Claude Code, Copilot, Cursor...) working in this repo: an Azure SRE Agent
lab, measured live on 2026-11-03, and a starting point for a production-ready deployment in your own tenant. Everything
below was measured in this lab or comes from Microsoft Learn (links in the README).

## 0. Rules for agents

- Read this file and the README before changing roles, network or agent settings.
- Never commit `terraform.tfvars`, state files or `.terraform/` (git-ignored). Use `terraform.tfvars.example` for
  new variables. Never put subscription IDs, tenant IDs, emails or keys in tracked files.
- Creating Azure resources costs money (the agent alone is about 288 EUR per month always-on): plan first, apply only
  when the human owner asks, and say what it will cost.
- Keep the agent least-privileged: `mode = "Review"`, `accessLevel = "Low"`, readers plus the two custom diagnostics
  roles. Never grant the roles in the "Never grant" row below. Do not configure the agent in the portal: it adds
  roles silently.
- Faults are switched with `terraform apply -var fault_<name>=true`; a plain `terraform apply` restores the healthy
  baseline. If the cross-region test is deployed, pass `-var cross_scope_test=true -var cross_scope_grant=true` on
  every apply, or Terraform destroys that resource group.
- Commands: `terraform init`, `terraform plan`, `terraform apply`, `terraform destroy` (see README for scenarios).

## 1. What this repo is today

- A **lab**, not a landing zone: one VNet, two small VMs, a Premium container registry behind a private endpoint, a
  web app pulling through it, Log Analytics, Key Vault, and switchable faults (`fault_*` variables) to break it.
- **The agent in code** (`sre-agent.tf`): `Microsoft.App/agents@2026-07-01` via `azapi`, user-assigned identity,
  `accessLevel = "Low"`, `mode = var.agent_mode` (default `Review`), pinned model (`defaultModel`), egress
  `AzureVNet` through the delegated subnet `snet-agent` (/27, `Microsoft.App/environments`), all egress allow-lists
  empty.
- **Least privilege** (`least-privilege.tf`): Reader, Monitoring Reader and Log Analytics Reader on the managed
  resource groups, a custom *Network Diagnostics Reader* (Network Watcher actions only), a custom *SRE Web
  Diagnostics Reader* (App Service diagnostics, explicitly NOT `Microsoft.Web/sites/config/list/action`), and an
  optional *SRE Responder* (restart/start/stop one web app, edit rules of one NSG), off by default
  (`agent_can_remediate = false`).
- **Cross-region test** (`cross-scope.tf`, off by default): a France Central resource group with an NSG, to prove that
  RBAC scope, not region, decides what the agent can see. If you re-apply the lab state that ran this test, pass
  `-var cross_scope_test=true -var cross_scope_grant=true`, or Terraform destroys that resource group.

## 2. Decisions already proven (keep them)

| Decision | Why (measured) |
|---|---|
| Deploy with code, not the portal | The portal agent got model `Automatic` and egress `Limited`, plus roles it never listed: Storage Blob Data Reader and, after connecting incidents, **Monitoring Contributor on the whole subscription** (= `*/read` everywhere plus write on alert rules). Code gives the exact model, network and roles. |
| `mode = Review` for incident plans | The portal default is `Autonomous`. In Autonomous mode the agent tried to restart the web app on its own (RBAC blocked it). |
| No OBO in practice | In chat, a refused read offers "Grant permissions": the command re-runs with the **user's** credentials (an Owner here). Train users to cancel; Autonomous threads cannot use OBO at all. |
| One agent per workload or team, not per region | One agent read resource groups in Sweden Central and France Central. Its region only sets where its data is stored. |
| Readers + 2 small custom roles | Enough to find the NSG rule behind the registry private-endpoint failure. |
| Never grant | Contributor/Owner, Website Contributor (the agent's own suggestion), Monitoring Contributor, Key Vault data roles, Storage Blob Data Reader, `sites/config/list/action`. |
| Role changes take about 5 minutes | A new Reader grant was still denied ~2 minutes later, allowed after ~5. |

## 3. Costs (measured, EUR and USD)

- AAU (meter "SRE Agent Unit", Azure Retail Prices API, 2026-11-03): Sweden Central / France Central 0.110 USD =
  0.0987 EUR; East US 0.100 USD = 0.0898 EUR; West Europe 0.136 USD = 0.1221 EUR. The region
  changes the bill by up to 36 %.
- Always-on = 4 AAU/h. Sweden Central: 0.39 EUR/h = 9.48 EUR/day = **about 288 EUR / 321 USD per agent per 730-hour
  month** (East US 262 EUR / 292 USD, West Europe 357 EUR / 397 USD).
  Stopping does not stop it; only deleting does. First 30 days of always-on are waived (trial, up to 3 agents).
- Active work today: 27 AAU in total (about 2.66 EUR): NSG chat diagnosis 10, automatic incident 8, onboarding 7,
  scheduled health check on the Fast tier 1.
- The monthly active cap defaults to 10,000 AAU (about 987 EUR); set it from the expected incident volume.
- Fewer agents is the main lever: one per workload or team, not per subscription or region.

## 4. Production checklist

Identity and access
- [ ] Separate subscription or resource-group scopes per workload; `managedResources` lists only those scopes.
- [ ] Assign the reader set + the two custom diagnostics roles at those scopes only; custom role
      `assignable_scopes` set to your scopes (today: the lab resource group).
- [ ] Add `Microsoft.Network/networkWatchers/connectivityCheck/action` to the Network Diagnostics Reader (missing).
- [ ] Azure Firewall visibility if you have one: Reader covers `azureFirewalls/read`,
      `firewallPolicies/read`, `ruleCollectionGroups/read`; logs via Log Analytics Reader on the workspace holding
      `AZFWNetworkRule`, `AZFWApplicationRule`, `AZFWNatRule`.
- [ ] Remediation only if asked: `agent_can_remediate = true` scoped to named resources, with a Review response plan.
- [ ] Azure Policy or a scheduled audit that alerts when any role is assigned to the agent identity outside code
      (the portal adds roles silently).
- [ ] SRE Agent user roles for people (Administrator for owners of the agent, lower roles for responders).

Network
- [ ] `agent_network_mode = "AzureVNet"` with a dedicated /27+ subnet delegated to `Microsoft.App/environments`,
      same region as the agent, in your hub or spoke, with its own NSG and routes through your
      firewall. There is no private endpoint *to* the agent; model calls and orchestration stay at Microsoft.
- [ ] Only needed for data-plane reach (apps, AMPLS-locked Log Analytics, databases behind private endpoints).
      Control-plane reads (ARM, metrics) work without it.

Model and data
- [ ] Azure OpenAI provider for EU Data Boundary; pin the model per region from
      `GET .../providers/Microsoft.App/locations/{region}/supportedAgentModels?api-version=2026-07-01`.
- [ ] Agent region = your data-residency region.

Operations
- [ ] Incident platform: Azure Monitor (no key) or PagerDuty/ServiceNow; response plans in **Review**, cooldown 3 h.
- [ ] Scheduled checks on the Fast tier with a run limit; switch their default Autonomous to Review.
- [ ] Monthly AAU cap set; cost alert on the agent resource.
- [ ] Put the 5xx metric alert in Terraform (`alert-...-web-5xx` was created by CLI during the lab, not in code).

Repo hygiene for a production copy
- [ ] Remove the lab-only parts (`fault_*`, test VMs, `cross-scope.tf`) or move them to a `lab/` module.
- [ ] Remote state (a private storage account), CI plan/apply with an OIDC federated identity, no secrets in
      tfvars.

## 5. Open questions not yet measured

- Azure Firewall scenario end to end.
- Behaviour with many resource groups per agent. In Microsoft's "Inside Azure SRE Agent Live" webinar, InEight
  (self-reported) kept each agent under 20 to 50 resources; 700+ resources per agent caused API throttling.
- AAU cost of a busy month of real incidents.
