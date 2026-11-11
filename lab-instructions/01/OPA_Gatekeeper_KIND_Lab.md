# OPA Gatekeeper on a local KIND cluster

Guided lab for Windows and PowerShell

Build a two-node Kubernetes cluster using KIND and Docker Desktop. Install OPA Gatekeeper, introduce an owner-label policy, and then prevent Pods from requesting root identities. Observe an accepted request, a policy rejection and a corrected request in each demonstration.

| Stage | What you will establish |
| --- | --- |
| Prepare Docker Desktop | The Linux container engine is running. |
| Create KIND cluster | One control-plane node and one worker are Ready. |
| Install Gatekeeper | The admission controller and audit components are available. |
| Require an owner label | A missing label causes an admission rejection. |
| Require non-root settings | A root Pod is rejected and a compliant Pod runs as UID 101. |
| Change enforcement mode | dryrun allows a violation; deny blocks a new request. |

### Before you begin

Use Windows 11 on an x64 computer, Docker Desktop with a working Linux container backend, and PowerShell 7. Allow approximately 75 to 100 minutes, including image downloads. The timing is a planning estimate. An administrator or instructor must prepare Docker Desktop and any required Windows virtualization features before the lab.

Recommended lab capacity is at least 4 logical CPUs and 8 GB of memory available to the Docker backend, plus free disk space for container images. This is a practical lab allowance rather than a vendor minimum. Internet access is required for tools and container images.

### Versions and files

The lab specifies KIND v0.33.0, a digest-pinned Kubernetes v1.36.4 node image, and Gatekeeper v3.23.1. The supplied NGINX examples retain the stable image tags used in the source demonstration. Those application tags can change; record their resolved image IDs during your run.

Extract the supplied lab ZIP so that the guide files and support folder sit directly inside C:\OPA\KIND-Lab. You will run commands from the support folder. Commands are written as individual PowerShell lines, without continuation backticks. Read the expected result before moving to the next step.

## 1 Prepare Docker Desktop and the tools

### Check the container engine

Open Docker Desktop and wait until the engine is running. Use Linux containers. In Settings, use the WSL 2 based engine if that is your prepared backend. KIND will create its own cluster as Docker containers; you do not need to enable Docker Desktop Kubernetes.

Open PowerShell 7 and run:

```powershell
$PSVersionTable.PSVersion
docker version
docker info --format '{{.OSType}}'
docker context show
```

Expected result: the PowerShell major version is 7; docker version shows both Client and Server sections; the operating-system type is linux. On a typical Windows Docker Desktop installation, the active Docker context is desktop-linux. A connection error means the engine is not ready or the selected Docker context is incorrect.

### Install KIND and kubectl if required

Check whether the tools already exist:

```powershell
kind version
kubectl version --client
```

If KIND is missing, install the specified release. If kubectl is missing, install it. Run only the installation commands you need:

```powershell
winget install -e --id Kubernetes.kind --version 0.33.0
winget install -e --id Kubernetes.kubectl
```

Close and reopen PowerShell 7 after installation, then repeat the version checks. If winget reports that the requested KIND version is unavailable, use the direct-download method on the next page. If an older KIND is already installed, prepare v0.33.0 before continuing.

The kubectl client must be within one minor version of this v1.36 cluster: v1.35, v1.36 or v1.37. Docker Desktop may already supply a suitable kubectl. Use Get-Command kubectl -All to see which executable PowerShell finds first. Do not create or overwrite a kubeconfig file manually.

### Checkpoint

Proceed when Docker can reach a Linux engine, kind version reports v0.33.0, and a compatible kubectl client is available. If a command fails, resolve it before creating the cluster.

## 2 Prepare the lab folder

### Open the supplied files

```powershell
Set-Location C:\qa-opa-labs\labs\01
Get-ChildItem
$ctx = 'kind-opa-demo'
$env:KIND_EXPERIMENTAL_PROVIDER = 'docker'
```

Expected result: the folder contains kind-config.yaml, the Gatekeeper release manifest, four numbered policy files, four example Pod files and two PowerShell toggle scripts. The ctx variable explicitly selects the lab Kubernetes context in later commands. Recreate this variable whenever you open a new PowerShell session.

| Files | Purpose |
| --- | --- |
| kind-config.yaml | Two-node KIND configuration with a pinned node image. |
| gatekeeper-v3.23.1.yaml | Unmodified upstream Gatekeeper installation manifest. |
| 01-required-labels-template.yaml and 02-owner-required.yaml | Owner-label policy logic and its scoped constraint. |
| 03-nonroot-template.yaml and 04-nonroot-required.yaml | Non-root policy logic and its scoped constraint. |
| before-owner-policy.yaml and after-owner-policy.yaml | Owner-label examples; both already satisfy the non-root rule. |
| nginx-root.yaml and nginx-nonroot.yaml | Root and non-root security examples; both have owner labels. |
| Enable-OPAConstraints.ps1 and Disable-OPAConstraints.ps1 | Set selected constraints to deny or dryrun in kind-opa-demo. |

### Alternative KIND installation

Use this method only if the earlier winget installation could not supply v0.33.0. It downloads the official Windows x64 binary to a user-owned tools folder and adds that folder to the current session PATH:

```powershell
$kindTools = Join-Path $env:LOCALAPPDATA 'OPA-KIND-Tools'
New-Item -ItemType Directory -Path $kindTools -Force | Out-Null
$kindUrl = 'https://kind.sigs.k8s.io/dl/v0.33.0/kind-windows-amd64'
Invoke-WebRequest -Uri $kindUrl -OutFile (Join-Path $kindTools 'kind.exe')
$env:Path = "$kindTools;$env:Path"
kind version
```

The PATH change above applies to this PowerShell session. If you use a new session, repeat the kindTools assignment and PATH line, or add the tools folder to your user PATH through Windows settings.

## 3 Create the KIND cluster

### Review the cluster definition

```powershell
Get-Content .\kind-config.yaml
kind get clusters
```

The configuration defines a Cluster with apiVersion kind.x-k8s.io/v1alpha4. Its nodes list contains one control-plane entry and one worker entry. Both use the supplied Kubernetes v1.36.4 image and digest. If a KIND cluster named opa-demo already exists, use the reset guidance before attempting a fresh run.

### Create and inspect the cluster

```powershell
kind create cluster --name opa-demo --config .\kind-config.yaml --wait 180s
kubectl config use-context $ctx
kubectl config current-context
kubectl --context $ctx wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context $ctx get nodes
kubectl --context $ctx version
docker ps --format 'table {{.Names}}	{{.Status}}'
```

Expected result: the Kubernetes context is kind-opa-demo. The nodes opa-demo-control-plane and opa-demo-worker are Ready and report v1.36.4. Docker also lists the two node containers. The first run may take several minutes while the node image downloads.

### Understand the components

Docker Desktop supplies the Linux container engine. KIND runs the Kubernetes nodes inside containers on that engine. kubectl sends requests to the API server identified by its context. Gatekeeper will run as Pods inside this new cluster.

### Create the demonstration namespace

```powershell
kubectl --context $ctx create namespace opa-demo
kubectl --context $ctx get namespace opa-demo
```

Expected result: namespace/opa-demo is created. This namespace will contain the demonstration Pods. The policies will match Pods in this namespace, while Gatekeeper runs in its own gatekeeper-system namespace.

The lab passes --context explicitly on cluster operations. If another cluster is present in kubeconfig, these commands still select kind-opa-demo. Keep the ctx variable set to that exact value.

## 4 Install OPA Gatekeeper

Gatekeeper connects Kubernetes admission requests to policy evaluation. Installing it creates the platform components and custom resource types. It does not yet introduce either demonstration rule.

### Apply the pinned release manifest

```powershell
kubectl --context $ctx apply -f .\gatekeeper-v3.23.1.yaml
$gk = 'gatekeeper-system'
kubectl --context $ctx wait --for=condition=Available deployment --all -n $gk --timeout=300s
kubectl --context $ctx get deployments,pods -n gatekeeper-system
kubectl --context $ctx get validatingwebhookconfiguration
kubectl --context $ctx get crd constrainttemplates.templates.gatekeeper.sh
```

Expected result: the controller-manager and audit deployments become Available and their Pods become Ready. The release normally creates three controller-manager replicas and one audit replica. The webhook list includes gatekeeper-validating-webhook-configuration, and the ConstraintTemplate CRD exists.

If a wait times out, stop and inspect the Pods and events. Do not interpret a later allowed request as evidence about a policy until Gatekeeper is healthy.

### What each policy resource will do

| Resource | Role in this lab |
| --- | --- |
| ConstraintTemplate | Defines the Rego logic, the generated constraint kind and any parameter schema. |
| Constraint | Chooses the objects to check, supplies parameters and sets the enforcement action. |
| Pod | The Kubernetes resource submitted for admission. |
| Audit status | Reports violations found on resources that already exist. |

Both templates use Rego v1 through targets.code, engine Rego and source.version v1. The ConstraintTemplate API version and the Rego language version describe different things.

### Readiness and failure behaviour

Controller readiness and a successful installation do not prove that a particular constraint has reached every controller. After introducing each rule, inspect its status and verify the expected admission result. The supplied upstream installation uses Gatekeeper's default admission failure behaviour; if its validation webhook is unavailable, matching requests can be allowed. Keep that operational behaviour separate from a policy decision.

## 5 Establish the owner label baseline

Start this section before installing either demonstration constraint. The example Pod deliberately lacks an owner label, while its security settings already request a non-root identity. That keeps the label test independent of the later security rule.

### Inspect and submit the request

```powershell
Get-Content .\before-owner-policy.yaml
kubectl --context $ctx create -f .\before-owner-policy.yaml
kubectl --context $ctx get pod before-policy -n opa-demo --show-labels
kubectl --context $ctx wait --for=condition=Ready pod/before-policy -n opa-demo --timeout=180s
```

Expected result: pod/before-policy is created and becomes Ready. Its labels include run=before-policy and do not include owner. The absence of a Gatekeeper constraint means the organisation-specific owner requirement is not enforced.

If the resource is created but the image cannot be downloaded, admission has succeeded. Investigate the image-pull problem separately; it is not a Gatekeeper denial.

### Review the Rego check

```powershell
Get-Content .\01-required-labels-template.yaml
Get-Content .\02-owner-required.yaml
```

The template reads input.review.object.metadata.labels. For every label named in input.parameters.labels, it reports a violation if that key is missing. The constraint supplies owner and selects Pods in the opa-demo namespace.

```powershell
violation contains {"msg": msg} if {
  labels := object.get(input.review.object.metadata, "labels", {})
  some label in input.parameters.labels
  not label in object.keys(labels)
  msg := sprintf("Missing required label: %v", [label])
}
```

This rule checks whether the key exists. An empty owner value still passes. The example does not validate a person's identity or ownership permissions.

### Checkpoint

Record that the missing-owner Pod was admitted before the rule existed. Leave it running for the next section so you can observe how a new policy affects an existing resource.

## 6 Introduce and test the owner policy

### Install the template and constraint

```powershell
kubectl --context $ctx apply -f .\01-required-labels-template.yaml
$ownerCrd = 'crd/k8sdemorequiredlabels.constraints.gatekeeper.sh'
kubectl --context $ctx wait --for=create $ownerCrd --timeout=90s
kubectl --context $ctx wait --for=condition=Established $ownerCrd --timeout=90s
kubectl --context $ctx apply -f .\02-owner-required.yaml
kubectl --context $ctx get K8sDemoRequiredLabels pods-must-have-owner -o yaml
```

Expected result: the generated CRD becomes Established and the constraint is created in deny mode. In status.byPod, controller entries should show enforced: true. If entries are absent, wait briefly and repeat the status command. If errors appear, inspect the template before continuing.

The existing before-policy Pod remains present. Gatekeeper does not remove it when the new rule is introduced. After the next audit cycle, the constraint status can report it as a violation.

### Submit the same missing-owner definition as a new request

```powershell
kubectl --context $ctx delete -f .\before-owner-policy.yaml
kubectl --context $ctx create -f .\before-owner-policy.yaml
```

Expected result: the create command is denied. The response identifies pods-must-have-owner and includes Missing required label: owner. This failure is intentional. No replacement Pod is created.

### Submit the corrected definition

```powershell
kubectl --context $ctx create -f .\after-owner-policy.yaml
kubectl --context $ctx wait --for=condition=Ready pod/after-policy -n opa-demo --timeout=180s
kubectl --context $ctx get pod after-policy -n opa-demo --show-labels
```

Expected result: pod/after-policy is created, becomes Ready and shows owner=michael. Compare the two YAML files: the material change for this rule is the owner label. Their different names identify the two examples.

If the missing-owner request is unexpectedly admitted, inspect Gatekeeper readiness and constraint status. Delete that example Pod before retrying the create command. An AlreadyExists error is not a policy decision.

## 7 Compare root and non root workloads

Keep the owner rule enabled. Both NGINX manifests contain owner=michael, so that rule will allow them. Do this comparison before installing the non-root constraint.

### Inspect the requested identities

```powershell
Get-Content .\nginx-root.yaml
Get-Content .\nginx-nonroot.yaml
```

| Setting | nginx-root | nginx-nonroot |
| --- | --- | --- |
| Image | nginx:stable | nginxinc/nginx-unprivileged:stable |
| runAsNonRoot | false | true |
| runAsUser and runAsGroup | 0 and 0 | 101 and 101 |
| Container HTTP port | 80 | 8080 |

### Create both Pods and inspect their identities

```powershell
kubectl --context $ctx create -f .\nginx-root.yaml
kubectl --context $ctx create -f .\nginx-nonroot.yaml
kubectl --context $ctx wait --for=condition=Ready pod/nginx-root -n opa-demo --timeout=180s
kubectl --context $ctx wait --for=condition=Ready pod/nginx-nonroot -n opa-demo --timeout=180s
kubectl --context $ctx exec -n opa-demo nginx-root -- id
kubectl --context $ctx exec -n opa-demo nginx-nonroot -- id
```

Expected result: both Pods are admitted. The root example returns UID/GID 0; the non-root example returns UID/GID 101. The id command reports the identity used for the exec process inside that container. The standard NGINX image can still use a root master process and lower-privilege workers.

containerPort describes the port the container uses. It does not create a Service or publish a port on the Windows host. No browser or ingress configuration is needed for these policy tests.

### Delete both before the next admission comparison

```powershell
kubectl --context $ctx delete -f .\nginx-root.yaml -f .\nginx-nonroot.yaml
```

Expected result: both Pods are deleted. Keep the YAML files unchanged. You will submit exactly these definitions again after installing the security rule.

## 8 Enforce the non root policy

### Inspect and install the second policy

```powershell
Get-Content .\03-nonroot-template.yaml
kubectl --context $ctx apply -f .\03-nonroot-template.yaml
$nonRootCrd = 'crd/k8sdemononroot.constraints.gatekeeper.sh'
kubectl --context $ctx wait --for=create $nonRootCrd --timeout=90s
kubectl --context $ctx wait --for=condition=Established $nonRootCrd --timeout=90s
kubectl --context $ctx apply -f .\04-nonroot-required.yaml
kubectl --context $ctx get K8sDemoNonRoot pods-must-run-as-nonroot -o yaml
```

Expected result: the second generated CRD becomes Established and the constraint exists in deny mode. Wait until controller status entries show enforced: true before testing new requests.

The Rego checks effective runAsNonRoot and runAsUser values. Container settings override the corresponding Pod settings; missing or null container values inherit the Pod value where available. The helper collects application, init and ephemeral container entries from the reviewed Pod. This lab exercises ordinary Pod creation; debug subresource admission requires its own webhook coverage check.

Every container must have effective runAsNonRoot: true and an explicit positive runAsUser. This is a deliberately stricter rule than relying only on the image's default user. Gatekeeper checks the declared settings; it does not pull the image to discover its user.

### Repeat the two requests

```powershell
kubectl --context $ctx create -f .\nginx-root.yaml
```

Expected result: admission is denied by pods-must-run-as-nonroot. The messages identify the nginx container and report both the missing true non-root setting and the absence of a positive UID. No root Pod is created.

```powershell
kubectl --context $ctx create -f .\nginx-nonroot.yaml
kubectl --context $ctx wait --for=condition=Ready pod/nginx-nonroot -n opa-demo --timeout=180s
kubectl --context $ctx exec -n opa-demo nginx-nonroot -- id
kubectl --context $ctx get pods -n opa-demo
```

Expected result: the non-root Pod is created and Ready, and id returns UID/GID 101. The listing includes after-policy and nginx-nonroot, with no nginx-root Pod. Both owner and non-root constraints are now active.

## 9 Explore dryrun and audit

### Prepare the supplied scripts

```powershell
Unblock-File .\Enable-OPAConstraints.ps1
Unblock-File .\Disable-OPAConstraints.ps1
.\Disable-OPAConstraints.ps1 -Constraint NonRoot
```

Expected result: the non-root constraint changes to dryrun. The scripts default to context kind-opa-demo and update the matching saved constraint YAML after a successful cluster patch. They keep Gatekeeper running. They preflight the selected resources, but a failure after one successful change can leave that change applied; read any reported error.

### Allow a violating Pod

```powershell
kubectl --context $ctx get K8sDemoNonRoot pods-must-run-as-nonroot -o yaml
kubectl --context $ctx create -f .\nginx-root.yaml
kubectl --context $ctx wait --for=condition=Ready pod/nginx-root -n opa-demo --timeout=180s
```

Wait for the mode change to reconcile before the create command. Expected result: the root Pod is admitted and becomes Ready because this rule is in dryrun. It still has an owner label, so the owner constraint remains satisfied.

### Observe the existing violation

```powershell
kubectl --context $ctx get K8sDemoNonRoot pods-must-run-as-nonroot -o yaml
```

Wait for an audit cycle and repeat the command as needed. Audit runs periodically; allow around one to two minutes initially. Look for status.auditTimestamp, status.totalViolations and an entry for nginx-root under status.violations. An absent violation immediately after creation can simply mean audit has not completed.

### Restore blocking and repeat the root request

```powershell
.\Enable-OPAConstraints.ps1 -Constraint NonRoot
kubectl --context $ctx get K8sDemoNonRoot pods-must-run-as-nonroot -o yaml
kubectl --context $ctx get pod nginx-root -n opa-demo
kubectl --context $ctx delete -f .\nginx-root.yaml
kubectl --context $ctx create -f .\nginx-root.yaml
```

Expected result: the existing root Pod remains after switching back to deny. Once deleted, its new create request is rejected again. The script changes the live mode and restores enforcementAction: deny in 04-nonroot-required.yaml. A deny mode change does not evict existing Pods.

## 10 Reset and record the result

### Capture your evidence

| Check | Result to record |
| --- | --- |
| Cluster and Gatekeeper | Both nodes Ready; Gatekeeper deployments Available. |
| Before owner policy | A Pod without owner was created. |
| After owner policy | Missing-owner request denied; corrected request admitted. |
| Before non-root policy | Both NGINX Pods admitted; identities were 0 and 101. |
| After non-root policy | Root request denied; non-root Pod Ready at UID 101. |
| Optional dryrun exercise | Root Pod admitted, audited, then blocked on a fresh request after deny. |

```powershell
$imagePath = '{.status.containerStatuses[0].imageID}'
kubectl --context $ctx get pod nginx-nonroot -n opa-demo -o jsonpath=$imagePath
```

Record the resolved application image before resetting the demonstration or deleting the cluster. A successful policy demonstration requires both an expected rejection and an expected acceptance. Keep the actual outputs with your course validation record.

### Repeat the demonstrations without rebuilding KIND

Run the following only when you want to start both before-policy phases again. The commands remove the two demonstration constraints and four named Pods. Gatekeeper and the templates remain installed.

```powershell
kubectl --context $ctx delete -f .\02-owner-required.yaml --ignore-not-found
kubectl --context $ctx delete -f .\04-nonroot-required.yaml --ignore-not-found
kubectl --context $ctx delete pod before-policy after-policy -n opa-demo --ignore-not-found
kubectl --context $ctx delete pod nginx-root nginx-nonroot -n opa-demo --ignore-not-found
```

Check that enforcementAction is deny in both numbered constraint YAML files before repeating sections 5 to 8. If you finished the optional mode exercise, its final enable command should already have restored that value. Reapply the constraints at the appropriate steps; the templates can be applied again.

### Remove the entire lab cluster

When finished with the lab, this deletes the named KIND cluster and everything inside it, including Gatekeeper and all demonstration resources:

```powershell
kind delete cluster --name opa-demo
kind get clusters
kubectl config get-contexts
```

Expected result: opa-demo no longer appears in the KIND cluster list and its kubeconfig entries are removed. Select another existing Kubernetes context if you need to continue other work. To repeat from a clean cluster, return to section 3.

## Troubleshooting and review

| Symptom | Action |
| --- | --- |
| Docker cannot reach the server | Start Docker Desktop. Confirm Linux containers and inspect docker context ls. |
| kind or kubectl is not recognised | Reopen PowerShell after installation; inspect Get-Command kind,kubectl -All. |
| Cluster name already exists | Inspect kind get clusters. Reuse it deliberately or delete opa-demo before a fresh run. |
| Gatekeeper wait times out | Inspect its Pods, deployments and namespace events before proceeding. |
| Constraint CRD is not created | Inspect the ConstraintTemplate status for compile or schema errors. |
| An invalid request is admitted | Check the explicit context, namespace, enforcement mode, controller status and webhook health. |
| An owner example fails the non-root rule | Use the revised Pod examples supplied with this lab; they contain UID 101 settings. |
| A Pod already exists | Delete only the named demo Pod before repeating its create request. |
| A created Pod is not Ready | Inspect describe output for pull failures or runtime problems; distinguish these from admission denial. |
| A downloaded script is blocked | Use the supplied Unblock-File commands. If organisational policy still prevents execution, use the manual toggle below. |

### Diagnostic commands

```powershell
kubectl --context $ctx get pods -n gatekeeper-system
kubectl --context $ctx get events -n gatekeeper-system --sort-by=.lastTimestamp
kubectl --context $ctx get constrainttemplate k8sdemononroot -o yaml
kubectl --context $ctx describe pod nginx-nonroot -n opa-demo
kind export logs .\kind-diagnostics --name opa-demo
```

### Manual alternative to the toggle scripts

Open 04-nonroot-required.yaml in VS Code. Change its single enforcementAction value to dryrun and save. Apply that file to the lab context, then inspect the live constraint. To restore blocking, edit the same value back to deny, save and apply again:

```powershell
kubectl --context $ctx apply -f .\04-nonroot-required.yaml
kubectl --context $ctx get K8sDemoNonRoot pods-must-run-as-nonroot -o yaml
```

Review: Which resource contains Rego? Which resource selects the namespace? Why does an existing violating Pod remain after deny is enabled? Why does an image-pull error differ from an admission denial?

## References and instructor preparation

### Source references

The instructions and version selections were checked against the following official sources on 11 November 2026. The Gatekeeper release manifest is included unchanged in the support folder.

| Source | URL |
| --- | --- |
| KIND quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| KIND v0.33.0 release and node images | https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0 |
| KIND cluster configuration | https://kind.sigs.k8s.io/docs/user/configuration/ |
| Docker Desktop for Windows | https://docs.docker.com/desktop/setup/install/windows-install/ |
| kubectl on Windows | https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/ |
| Gatekeeper installation | https://open-policy-agent.github.io/gatekeeper/website/docs/install/ |
| Gatekeeper templates and Rego v1 | https://open-policy-agent.github.io/gatekeeper/website/docs/constrainttemplates/ |
| Gatekeeper enforcement modes | https://open-policy-agent.github.io/gatekeeper/website/docs/violations/ |
| Gatekeeper webhook behaviour | https://open-policy-agent.github.io/gatekeeper/website/docs/customize-admission/ |
| Kubernetes security context | https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| NGINX unprivileged image | https://github.com/nginx/docker-nginx-unprivileged |

### Prepare the delivery environment

Before delivery, run the full procedure on the intended Windows image. Confirm available memory, tool-install permissions, registry access, script execution and the expected admission messages. Pin the NGINX application images to the digests observed in that rehearsal if exact repeatability is required. Keep the root and non-root Pod files identical between their before and after phases.

The included policy templates were compiled in strict mode and evaluated against 19 local decision cases using OPA v1.17.1. This checks Rego decisions for representative Pod inputs. It does not establish Windows tool installation, Gatekeeper reconciliation, webhook behaviour or NGINX startup in the learner environment. Use the evidence table to record that rehearsal.

The original source bundle is retained separately. This lab replaces its historical session log with a repeatable procedure, aligns the filenames, changes the scripts' default context to kind-opa-demo and gives both owner-label examples compliant non-root settings.
