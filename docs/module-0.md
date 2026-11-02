# Module 0 - Deploy with Terraform

For the Azure deployment operator. Use **PowerShell 7.5+, Terraform 1.9 to 1.x, Git and Azure CLI**. You need resource creation, custom-role/assignment and Entra application permissions. Confirm provider registration, model quota and ongoing costs before starting.

<details>
<summary>Deployment prerequisites: components, permissions and policy checklist</summary>

## Customer deployment: components and policy checklist

The lab uses **public, identity-protected endpoints** and synthetic workshop
data. Review the following resource types, permissions and policy requirements
with your deployment team.

This inventory covers the foundation plus the selected `architecture-docs`
workload, not just the services participants create during exercises. Review
the actual Terraform plans for the configuration selected by your inputs.

| Component | Azure resource type / provider | Configuration and purpose |
|---|---|---|
| Dedicated resource groups | `Microsoft.Resources/subscriptions/resourceGroups` | Foundation, workload runtime and extension-authoring boundary. Use new lab groups, not production groups. |
| Microsoft Foundry | `Microsoft.CognitiveServices/accounts`, `/projects`, `/deployments` | AIServices S0 account, team/facilitator projects and workload-owned chat, judge and embedding deployments. Model/version/SKU/capacity are explicit deployment inputs; verify quota and availability. |
| API Management | `Microsoft.ApiManagement/service` | BasicV2 capacity 1 in the default `lite` profile; StandardV2 capacity 1 in the alternative profile. Public gateway, managed identity, model/API routes, policies, native MCP APIs/tools and project connections. Not the separate preview AI Gateway resource. |
| API Center | `Microsoft.ApiCenter/services` | Free tier; API/MCP catalog registrations, versions, definitions and metadata. |
| Azure AI Search | `Microsoft.Search/searchServices` | Reference input selects S1, three replicas/one partition and standard semantic/agentic billing; unoverridden native defaults remain Basic, one replica/partition. Entra authentication; indexes, ingestion, embedding/vectorizer and preview knowledge source/base/MCP connection. Required for this scenario even if B1 is not attempted. Review the actual plan. |
| Blob Storage | `Microsoft.Storage/storageAccounts` | Standard LRS; shared keys and anonymous blob access disabled. Synthetic documents/proposals/templates/glossary and Search ingestion. |
| Key Vault | `Microsoft.KeyVault/vaults` | Standard, RBAC; seven-day soft delete and purge protection disabled in the current disposable-lab profile. Check any policy requiring purge protection. |
| Container Registry | `Microsoft.ContainerRegistry/registries` | Basic, admin account disabled; remote Linux image builds and immutable application images. Build access to required base-image/package registries is needed. |
| Container Apps | `Microsoft.App/managedEnvironments`, `/containerApps` | Shared environment and two externally reachable authenticated apps: documentation backend and toolkit. Each app has one replica, 0.25 vCPU and 0.5 GiB. Separate extension group supports B2 authoring. |
| Content Safety | `Microsoft.CognitiveServices/accounts` | Separate ContentSafety S0 account and gateway backend for B4. This prerequisite is provisioned even if the bonus is not attempted. |
| Traces and logs | `Microsoft.OperationalInsights/workspaces`, `Microsoft.Insights/components` | Log Analytics PerGB2018 and workspace-based Application Insights, project connections and ingestion/query grants. |
| Monitoring | `Microsoft.Insights/diagnosticSettings` | Application, gateway and container diagnostics. |
| Identity and authorization | `Microsoft.ManagedIdentity/userAssignedIdentities`, `Microsoft.Authorization/roleDefinitions`, `/roleAssignments` | Application/service managed identities, scoped runtime/participant grants and custom authoring roles; some definitions/grants are subscription-scoped. |
| Optional semantic cache | `Microsoft.Cache/redisEnterprise`, `/databases` | Only when `semantic_cache_enabled` is true: Balanced_B0, RediSearch, TLS, no HA, public endpoint and explicitly enabled access-key authentication, with a Key Vault-backed APIM connection. Separate cost/key-policy approval required. |

**Entra tenant changes are also required:** workload app registration, service
principal, exposed delegated scope, Azure CLI preauthorization and application
role assignments for teams, gateway and separately selected human librarians.
Azure subscription permissions alone do not authorize these tenant operations.
Participant grants are direct roster assignments, not membership in a workshop
group, and shared-service authoring is not hard team isolation.

**Before deploying, check:**

- **Policy and regions:** allow the listed resource providers, child-resource
  types, SKUs and public endpoints, including Storage, Key Vault, Search, ACR,
  and Container Apps ingress. France Central is preferred; Sweden Central and
  West Europe are supported selections. Validate each service/model in the
  selected region. A public-endpoint exception for one service does not
  automatically cover the rest. Review model deployment SKU/data-processing
  geography separately: a `GlobalStandard` deployment in a European resource
  region is not a guarantee of EU-only inference processing.
- **Operator rights:** resource creation, custom-role definition and assignment
  rights at the plan's actual scopes and tenant-approved
  Graph/app-registration/app-role operations. Resource-group Contributor alone
  is insufficient. Have administrators approve/register missing providers
  before deployment.
- **Quota and network access:** model deployments/TPM, Search, APIM and container
  capacity; operator/participant access to Azure, Entra, package sources and
  required public service endpoints. No private-endpoint/VNet alternative is
  included in this lab profile.
- **Costs and lifecycle:** review ongoing service and model costs. Budget
  monitoring and teardown are managed by the subscription owner; the lab does
  not deploy automatic budget- or expiry-based deletion.
- **Deployment:** follow the steps below and review the separate
  foundation/access/workload plans before any apply. Keep state and deployment
  inputs private. Deployment-specific troubleshooting is in the
  [deployment notes](exercise-readiness.md).

For Cloud Shell deployments, configure persistent storage separately and keep
deployment state and private inputs backed up.

</details>

## 1. Sign in and prepare inputs

Start working with a fresh copy of the hackathon repository by running `git clone` as instructed below. This downloads the repository into a new local folder, `foundry-lab`. Run the blocks in order in the same terminal; review each plan before confirming its apply.

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
if ($env:TF_DATA_DIR) { throw 'Use a fresh terminal without TF_DATA_DIR.' }
git clone https://github.com/mikkokallio/foundry-hackathon.git foundry-lab
Set-Location foundry-lab
New-Item -ItemType Directory -Path .\out -Force | Out-Null
Copy-Item .\infra\people.example.json .\out\people.private.json
```

Edit **`out\people.private.json`**: fill in `publisher_email`, the monitored APIM contact. Librarians and team members can also be added now, or later in Step 3. Keep this file private. The generator supplies Contoso, five team projects (alpha, beta, gamma, delta, epsilon), France Central, Basic v2 APIM, Standard Search with three replicas, and the shared model/cache/limit defaults.

<details>
<summary>Sample people.private.json</summary>

- `publisher_email`: APIM's monitored contact email; grants no permissions.
- `librarians` and team members: actual sign-in UPNs in the deployment tenant, not necessarily their contact emails. Librarians can review/publish proposals and may also be participants.

This fictional example uses John's contact email and his sign-in UPN in the
same Contoso directory as all ten participants. Replace them with real values.
UPNs can use a verified domain such as `contoso.com`; `onmicrosoft.com` is not
required. Use the actual UPN shown in Microsoft Entra ID.

```json
{
  "publisher_email": "john.publisher@contoso.com",
  "librarians": ["john.publisher@contoso.onmicrosoft.com"],
  "teams": {
    "alpha": ["dummy1@contoso.onmicrosoft.com", "dummy2@contoso.onmicrosoft.com"],
    "beta": ["dummy3@contoso.onmicrosoft.com", "dummy4@contoso.onmicrosoft.com"],
    "gamma": ["dummy5@contoso.onmicrosoft.com", "dummy6@contoso.onmicrosoft.com"],
    "delta": ["dummy7@contoso.onmicrosoft.com", "dummy8@contoso.onmicrosoft.com"],
    "epsilon": ["dummy9@contoso.onmicrosoft.com", "dummy10@contoso.onmicrosoft.com"]
  }
}
```

</details>


```powershell
az login
$subscription = Read-Host 'Target subscription ID'
.\infra\scripts\New-NativeDeploymentInputs.ps1 -SubscriptionId $subscription `
  -PeopleFile .\out\people.private.json -OutputDirectory .\out -FoundationOnly
$out = (Resolve-Path .\out).Path
$f = (Resolve-Path .\infra\foundation).Path
$a = (Resolve-Path .\infra\access).Path
$w = (Resolve-Path .\scenarios\architecture-docs\infra).Path
$config = Get-Content "$out\native-foundation.tfvars.json" -Raw | ConvertFrom-Json
az account set --subscription $config.subscription_id
```

## 2. Deploy shared services

```powershell
$vars = (Resolve-Path "$out\native-foundation.tfvars.json").Path
$plan = Join-Path $out 'foundation.tfplan'
terraform "-chdir=$f" init
terraform "-chdir=$f" plan "-var-file=$vars" "-out=$plan"
if ((Read-Host 'Review target, costs and changes. Type APPLY') -cne 'APPLY') { throw 'Stopped' }
terraform "-chdir=$f" apply $plan
$foundation = terraform "-chdir=$f" output -json foundation |
  ConvertFrom-Json -AsHashtable
```

## 3. Grant access and build the applications

Complete the same private people file: `librarians` lists the humans allowed to review/publish documents; `teams` maps participating teams to member UPNs. Include at least one member per listed team; remove keys for entirely unused teams. Images are built remotely in ACR; local Docker is not needed.

```powershell
.\infra\scripts\New-NativeDeploymentInputs.ps1 -SubscriptionId $config.subscription_id `
  -PeopleFile "$out\people.private.json" -OutputDirectory $out
$vars = (Resolve-Path "$out\native-access.tfvars.json").Path
$plan = Join-Path $out 'access.tfplan'
$ai = Get-Content $vars -Raw | ConvertFrom-Json -AsHashtable
$ai.foundation = $foundation
$ai | ConvertTo-Json -Depth 50 | Set-Content $vars
terraform "-chdir=$a" init
terraform "-chdir=$a" plan "-var-file=$vars" "-out=$plan"
if ((Read-Host 'Review users, roles and scopes. Type APPLY') -cne 'APPLY') { throw 'Stopped' }
terraform "-chdir=$a" apply $plan
$access = terraform "-chdir=$a" output -json deployment_access |
  ConvertFrom-Json -AsHashtable
$wi = Get-Content "$out\native-workload.tfvars.json" -Raw | ConvertFrom-Json -AsHashtable
$build = .\infra\scripts\Build-WorkloadImages.ps1 -Scenario architecture-docs `
  -WorkloadName $wi.workload_name -Foundation $foundation -OutputDirectory "$out\images" -PassThru
```

## 4. Deploy models, APIs and knowledge

The build result supplies its JSON file automatically; no path or digest copy/paste is needed.

```powershell
$vars = (Resolve-Path "$out\native-workload.tfvars.json").Path
$plan = Join-Path $out 'workload.tfplan'
$wi.foundation = $foundation; $wi.participant_members = $access.members
if (-not $build.Complete) { throw 'Both application images must be built before continuing.' }
$wi.runtime_images = Get-Content $build.ImageFile -Raw | ConvertFrom-Json -AsHashtable
$wi | ConvertTo-Json -Depth 50 | Set-Content $vars
terraform "-chdir=$w" init
terraform "-chdir=$w" plan "-var-file=$vars" "-out=$plan"
if ((Read-Host 'Review models, images, identities and costs. Type APPLY') -cne 'APPLY') { throw 'Stopped' }
terraform "-chdir=$w" apply $plan
terraform "-chdir=$w" output -json knowledge
```

Workload apply also populates storage, runs Search ingestion and creates the knowledge connections. Confirm ingestion succeeded; do not run a separate initializer after a successful apply.

## 5. Export and hand over the team packs

```powershell
terraform "-chdir=$f" output -json | Set-Content "$out\foundation.outputs.json"
terraform "-chdir=$w" output -json | Set-Content "$out\workload.outputs.json"
@{
  subscription_id = $foundation.subscription_id; tenant_id = $foundation.tenant_id
  workload_name = $wi.workload_name
  workload_inputs = @{ organization_name = $wi.organization_name; reference_date = $wi.reference_date }
} | ConvertTo-Json -Depth 50 | Set-Content "$out\export-inputs.json"
foreach ($team in $ai.teams.Keys) {
  .\scenarios\architecture-docs\scripts\Export-ExerciseInputs.ps1 `
    -FoundationOutputs "$out\foundation.outputs.json" `
    -WorkloadOutputs "$out\workload.outputs.json" `
    -Inputs "$out\export-inputs.json" -Team $team -OutputDirectory "$out\packs\$team"
}
```

Give the facilitator the folders in **`out\packs\<team>`**. Each team receives only its own folder and [Participant: start here](../PARTICIPANT-START.md); for Cloud Shell setup, its `workshop.json` alone is enough. Never distribute Terraform state, plans or roster inputs. Before handover, have a non-admin test user run `lab check` using its team configuration.

<details>
<summary>Input field definitions and deployed inventory</summary>

Input schemas: [foundation](../infra/foundation/variables.tf), [access](../infra/access/versions.tf), [workload](../scenarios/architecture-docs/infra/variables.tf) and [models](../scenarios/architecture-docs/infra/models.tf). Use native Terraform inputs, not the differently shaped composition JSON example. The commands add applied `foundation`, resolved `participant_members` and built `runtime_images`; do not fill those with placeholders.

Step 1 generates only `native-foundation.tfvars.json`; Step 3 reuses it and adds `native-access.tfvars.json` and `native-workload.tfvars.json`. Existing access/workload inputs are not overwritten. Use actual tenant UPNs or object IDs for people; a guest's sign-in UPN can differ from their email.

Before granting access, remove an absent person's entry, not their whole team. Remove the team key only if nobody remains. If access was already applied, changing the people file alone does not revoke it: update the access inputs and review/apply an access plan using the same Terraform state.

| Deployed capability | Purpose |
|---|---|
| Foundry resource, team projects and models | Agent/model execution |
| API Management and Entra applications/roles | Authenticated model, REST and MCP gateways |
| API Center | API catalog |
| AI Search, indexes, ingestion and knowledge connections | Document retrieval |
| Storage and document/proposal containers | Lab content |
| Key Vault | Approved secret storage |
| ACR and Container Apps | Backend/toolkit images and services |
| Log Analytics and Application Insights | Logs, traces and usage |
| Scoped human and managed-identity grants | Service access |
| Optional Redis | Semantic cache, only when explicitly enabled |

</details>

<details>
<summary>Troubleshooting, state and teardown</summary>

- **Permissions/provider/quota failure:** resolve the named prerequisite in the selected subscription before continuing. Check the explicitly selected model/SKU capacity, not just model availability.
- **Interrupted apply or build:** retain this checkout and all inputs/state. Check whether the original operation is still running before retrying. After a failed apply, review a new plan against the same state; do not replay a stale plan.
- **State:** securely back up each root's `terraform.tfstate` and this deployment's inputs. Resume from that state, never from a fresh checkout. Do not mix these native states with another deployment route.
- **Cloud Shell:** keep the checkout, inputs and state in mounted persistent storage. An ephemeral session can discard local files when it ends.
- **Access failure:** verify target-tenant sign-in, guest invitation acceptance and role propagation. Test with the assigned non-admin identity, not only the operator.
- **Teardown:** resources keep billing until removed. Review destroy plans from the owning states; remove workload, then access, then foundation.

</details>
