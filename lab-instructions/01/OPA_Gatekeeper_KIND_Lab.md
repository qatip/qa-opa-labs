# OPA Gatekeeper on a local KIND cluster

Guided lab for Windows and PowerShell

© 2026 QA Michael Coulling-Green. All rights reserved.

Build a two-node Kubernetes cluster using KIND and Docker Desktop. Install OPA Gatekeeper, introduce an owner-label policy, and then prevent Pods from requesting root identities. Observe an accepted request, a policy rejection and a corrected request in each demonstration.

| Stage | What you will establish |
| --- | --- |
| Prepare Docker Desktop | The Linux container engine is running. |
| Create KIND cluster | One control-plane node and one worker are Ready. |
| Install Gatekeeper | The admission controller and audit components are available. |
| Require an owner label | A missing label causes an admission rejection. |
| Require non-root settings | A root Pod is rejected and a compliant Pod runs as UID 101. |
| Explore OPA in VS Code | Inspect inputs, evaluate Rego and test a local policy change. |
| Change enforcement mode | dryrun allows a violation; deny blocks a new request. |

### Before you begin

Use Windows 11 on an x64 computer, Docker Desktop with a working Linux container backend, PowerShell 7, and Visual Studio Code. Allow approximately 75 to 100 minutes for the Kubernetes procedure, plus 30 to 40 minutes for the VS Code exercises. Include extra time for image and tool downloads. The timing is a planning estimate. An administrator or instructor must prepare Docker Desktop and any required Windows virtualization features before the lab.

Recommended lab capacity is at least 4 logical CPUs and 8 GB of memory available to the Docker backend, plus free disk space for container images. This is a practical lab allowance rather than a vendor minimum. Internet access is required for tools and container images.

### Versions and files

The lab specifies KIND v0.33.0, a digest-pinned Kubernetes v1.36.4 node image, and Gatekeeper v3.23.1. The supplied NGINX examples retain the stable image tags used in the source demonstration. Those application tags can change; record their resolved image IDs during your run.

The course repository has already been cloned to C:\qa-opa-labs. The instructions for this lab are in lab-instructions\01, and its files are in labs\01. Run the lab commands from C:\qa-opa-labs\labs\01. Commands are individual PowerShell lines, without continuation backticks. Read each expected result before moving on.

## 1 Prepare Docker Desktop and the tools

### Check the container engine

There are three separate tools here. Docker provides the engine that runs the node containers. KIND creates and removes the Kubernetes cluster on that engine. kubectl manages resources inside the cluster. A Docker context selects a container engine; a Kubernetes context selects a Kubernetes API endpoint. Checking both avoids confusing the two connections.

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

| Repository location | Purpose |
| --- | --- |
| C:\qa-opa-labs | Root of the cloned course repository. |
| lab-instructions\01 | Markdown instructions and Word guide for this lab. |
| labs\01 | YAML, scripts, policies, inputs, tests and tools. |
| labs\01\.vscode\settings.json | Settings used when labs\01 is opened as a VS Code folder. |

You do not need to extract or move the lab files after the repository clone. An ordinary PowerShell window can run the commands below, or use the integrated terminal in VS Code. The Set-Location command makes later relative file paths resolve against labs\01.

The YAML files describe desired Kubernetes resources. Reading a file does not deploy it: kubectl create or apply submits it to the API server. The PowerShell scripts automate later mode changes. Keep these files together so their relative paths resolve consistently. The ctx variable is a reusable context name, while KIND_EXPERIMENTAL_PROVIDER tells KIND to use Docker for cluster creation.

```powershell
Set-Location C:\qa-opa-labs\labs\01
Get-ChildItem
$ctx = 'kind-opa-demo'
$env:KIND_EXPERIMENTAL_PROVIDER = 'docker'
```

Expected result: the folder contains kind-config.yaml, the Gatekeeper release manifest, four numbered policy files, four example Pod files two PowerShell toggle scripts and folders for the local OPA exercises. The ctx variable explicitly selects the lab Kubernetes context in later commands. Recreate this variable whenever you open a new PowerShell session.

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

KIND starts two Linux containers and bootstraps Kubernetes inside them. The control-plane node hosts components including the API server, scheduler and cluster state. The worker provides capacity for the lab workloads. The generated kubeconfig connection lets kubectl reach that API server. These node containers are the cluster infrastructure; the demonstration Pods are resources created later inside it.

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

A namespace groups namespaced Kubernetes resources and gives our policy a clear workload scope. Naming opa-demo in a constraint does not install Gatekeeper there: it selects which Pods the rule evaluates. This lets the lab policies target the examples without applying the same requirements to Gatekeeper's own Pods.

```powershell
kubectl --context $ctx create namespace opa-demo
kubectl --context $ctx get namespace opa-demo
```

Expected result: namespace/opa-demo is created. This namespace will contain the demonstration Pods. The policies will match Pods in this namespace, while Gatekeeper runs in its own gatekeeper-system namespace.

The lab passes --context explicitly on cluster operations. If another cluster is present in kubeconfig, these commands still select kind-opa-demo. Keep the ctx variable set to that exact value.

## 4 Install OPA Gatekeeper

Gatekeeper connects Kubernetes admission requests to policy evaluation. Installing it creates the platform components and custom resource types. It does not yet introduce either demonstration rule.

### Apply the pinned release manifest

The manifest creates several resources together, including the Gatekeeper deployments, permissions, custom resource definitions and admission webhook configuration. The controller-manager handles admission and policy reconciliation. The audit component checks resources that already exist. OPA is embedded in Gatekeeper; you do not need to deploy a separate OPA server for the Kubernetes demonstrations.

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

When you submit a Pod, kubectl contacts the Kubernetes API server. The API server calls Gatekeeper during admission, and Gatekeeper evaluates applicable policies with OPA. A deny result with violations makes the API server reject the request. An accepted request can be stored, scheduled and started afterward. Admission acceptance therefore happens before container readiness.

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

This establishes a control result: the Pod is valid Kubernetes even though it lacks our organisation's owner label. Kubernetes validates its built-in schema, but that does not automatically introduce this business requirement. The comparison later shows what changes when the same missing-label condition is evaluated under an installed policy.

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

```rego
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

These are two separate API operations. The template teaches Gatekeeper the rule and causes a CustomResourceDefinition, or CRD, to register K8sDemoRequiredLabels as a Kubernetes resource type. Waiting for that CRD prevents submitting the constraint before its type exists. The constraint then activates this rule for selected Pods, passes owner as a parameter and requests deny enforcement.

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

Deleting the baseline Pod makes this a new CREATE request rather than an update to an existing object. The file still has the same missing label. The significant environmental change is that the owner constraint is now active. A webhook denial proves the request reached admission but was not persisted as a replacement Pod.

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

runAsUser and runAsGroup specify Linux process IDs inside the container; they are unrelated to the Kubernetes user submitting the request. UID 0 is root. runAsNonRoot asks Kubernetes to require a non-root identity at startup. Setting an explicit UID also makes the requested identity visible to a policy without inspecting the container image.

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

The owner and non-root constraints now evaluate different properties of the same Pod. Satisfying one does not override a violation of the other. The non-root template resolves Pod settings and container overrides before checking each container. The root example violates two requirements, so two messages are expected; the non-root example satisfies both.

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

## 9 Work with OPA in VS Code

This exercise uses OPA directly from the VS Code terminal. You can inspect policy inputs and decisions without making Kubernetes API requests. Keep the cluster running; the local exercise uses separate policy copies and does not change the constraints already installed.

### Open the workspace and inspect the files

For this exercise, use labs\01 as the VS Code workspace root. If you need the guide in that window, use File > Open File to open C:\qa-opa-labs\lab-instructions\01\OPA_Gatekeeper_KIND_Lab.md. Opening the guide file does not change the workspace root.

```powershell
Set-Location C:\qa-opa-labs\labs\01
code -n .
```

Open C:\qa-opa-labs\labs\01 as the folder for this separate VS Code window. The -n option opens a new window, so your repository window can stay open. If code is not recognised, use File > New Window, then File > Open Folder and select that lab folder. Choose Terminal > New Terminal with PowerShell 7, then confirm the working folder:

```powershell
Set-Location C:\qa-opa-labs\labs\01
```

| Location | What to look for |
| --- | --- |
| policies/owner.rego and policies/nonroot.rego | Standalone copies of the Rego extracted from the two templates. |
| inputs/*.json | Sample Pod inputs using review.object and parameters. |
| tests/*.rego and tests/fixtures.json | Automated checks of representative decisions. |
| reference/*.rego.txt | Original policy text for restoring your local exercise. |

Open owner.rego beside 01-required-labels-template.yaml. The code beneath source.rego in the template is the same policy as the standalone file, without the YAML wrapper. The YAML also describes a Kubernetes custom resource; OPA itself evaluates the Rego and supplied data.

### Download the pinned Windows OPA CLI

```powershell
$opaUrl = 'https://openpolicyagent.org/downloads/v1.17.1/opa_windows_amd64.exe'
Invoke-WebRequest -Uri $opaUrl -OutFile .\tools\opa.exe
Unblock-File .\tools\opa.exe
.\tools\opa.exe version
```

Expected result: OPA reports version 1.17.1. The executable runs directly on Windows; it does not connect to the cluster. Using its explicit path avoids a machine-wide PATH change. This version matches the OPA dependency recorded for the selected Gatekeeper release.

### Optional editor support

In Extensions, search for Open Policy Agent and install the extension with identifier tsandall.opa. The lab-local .vscode/settings.json points to ${workspaceFolder}/tools/opa.exe and enables strict syntax checks on save. Open labs\01 as the workspace folder so these settings apply; opening only C:\qa-opa-labs does not load settings from its nested labs\01 folder. The terminal commands remain usable with or without the extension.

## 10 Evaluate and test Rego locally

### Understand the input and decision

Open inputs/owner-missing.json and inputs/owner-present.json side by side. review.object contains the Pod definition, including its metadata and spec. parameters.labels supplies the owner requirement normally supplied by the constraint. These files contain the fields this policy needs rather than a complete Kubernetes AdmissionReview message.

Open policies/owner.rego. Its package gives the query namespace, and violation is a set of messages. OPA exposes a package under data, so data.k8sdemorequiredlabels.violation queries this policy's violations. An empty set means this rule found no violations for this input.

```powershell
.\tools\opa.exe check --strict .\policies
$ownerQuery = 'data.k8sdemorequiredlabels.violation'
$ownerPolicy = '.\policies\owner.rego'
.\tools\opa.exe eval -f pretty -d $ownerPolicy -i .\inputs\owner-missing.json $ownerQuery
.\tools\opa.exe eval -f pretty -d $ownerPolicy -i .\inputs\owner-present.json $ownerQuery
```

Expected result: check produces no errors. The first evaluation returns a message containing Missing required label: owner; the second returns []. OPA has calculated data, not created or denied a Kubernetes resource. Gatekeeper interprets such violations according to the matching constraint and enforcement action.

The -d option loads a policy file; -i supplies the JSON input for this evaluation; -f pretty makes the result easier to read. The final argument is the query. A successful eval command can return violations: successful evaluation and a compliant input are separate outcomes.

### Evaluate the security examples

```powershell
$nonRootQuery = 'data.k8sdemononroot.violation'
$nonRootPolicy = '.\policies\nonroot.rego'
.\tools\opa.exe eval -f pretty -d $nonRootPolicy -i .\inputs\nginx-root.json $nonRootQuery
.\tools\opa.exe eval -f pretty -d $nonRootPolicy -i .\inputs\nginx-nonroot.json $nonRootQuery
```

Expected result: the root input returns two violation messages and the non-root input returns []. Message order is not significant because violation is a set. Change runAsUser in the non-root input to 0, save, evaluate again and predict which message should appear. Restore it to 101 afterward.

### Run the supplied policy tests

```powershell
.\tools\opa.exe test .\policies .\tests -v
```

Expected result: all six tests pass. Open the test files to see how with input as replaces the input for one evaluation. The tests cover missing and present owner labels, compliant non-root settings, root settings, a container override and an init container requesting root. The tests evaluate policy logic; they do not exercise Gatekeeper matching or admission.

## 11 Change a policy locally

### Explore a gap in the original requirement

The original owner rule requires the label key to exist. It deliberately permits owner with an empty string. Open inputs/owner-empty.json, inspect its owner value and evaluate it:

```powershell
.\tools\opa.exe eval -f pretty -d $ownerPolicy -i .\inputs\owner-empty.json $ownerQuery
```

Expected result: []. Suppose the requirement changes to say that every required label must also have a non-empty value. Add the following rule below the existing rule in policies/owner.rego. Keep the existing package declaration and missing-label rule:

```rego
violation contains {"msg": msg} if {
  labels := object.get(input.review.object.metadata, "labels", {})
  some label in input.parameters.labels
  value := labels[label]
  trim_space(value) == ""
  msg := sprintf("Required label %v must not be empty", [label])
}
```

Both rules contribute to the same violation set. The new rule checks a present value and treats whitespace-only values as empty. The existing rule still handles missing keys. Save the file, check its syntax and repeat the evaluation:

```powershell
.\tools\opa.exe check --strict .\policies\owner.rego
.\tools\opa.exe eval -f pretty -d $ownerPolicy -i .\inputs\owner-empty.json $ownerQuery
```

Expected result: the empty-owner input now produces Required label owner must not be empty. Add a regression test to tests/owner_test.rego so the new behaviour is recorded:

```rego
test_empty_owner_rejected if {
  violations := policy.violation with input as data.fixtures.owner_empty
  count(violations) == 1
}
```

```powershell
.\tools\opa.exe test .\policies .\tests -v
```

Expected result: seven tests pass. The extra test protects the new requirement while the earlier tests check existing behaviour.

### Relate the local change to Gatekeeper

The live Kubernetes policy has not changed. Gatekeeper reads the ConstraintTemplate installed through the API, not this local .rego file. Deploying a policy change would require updating the source.rego block in the template and applying it, then verifying reconciliation and admission. Leave that as a discussion here so the working Kubernetes comparison stays consistent.

```powershell
Copy-Item .\reference\owner.rego.txt .\policies\owner.rego -Force
```

Restore the local policy with the command above. Remove the test_empty_owner_rejected block you added and rerun the tests; the original six should pass again. Leave the other supplied tests in place.

## 12 Explore dryrun and audit

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

Admission and audit answer different questions. Admission evaluates a request before it is persisted. Audit examines objects that exist in the cluster. A rejected CREATE request leaves no Pod for audit to find. Here dryrun permits the root Pod to exist, giving the audit component an object it can report. Changing the action controls enforcement rather than changing the Rego rule.

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

## 13 Reset and record the result

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

The constraints and templates are cluster-scoped resources, even though their match rules select Pods in opa-demo. Removing demonstration Pods alone therefore leaves the policies active. This reset explicitly removes the constraints to recreate the original before-policy conditions, while keeping Gatekeeper and the generated resource types available for reuse.

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
| Local OPA returns an unexpected result | Check the query package, input path and saved file. Local evaluation does not apply the constraint match or enforcement action. |

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

The instructions and version selections were checked against the following official sources on 11 November 2026. The Gatekeeper release manifest is included unchanged in the lab folder.

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
| OPA Windows download | https://www.openpolicyagent.org/docs |
| OPA CLI commands | https://www.openpolicyagent.org/docs/cli |
| OPA policy testing | https://www.openpolicyagent.org/docs/policy-testing |
| OPA VS Code extension | https://github.com/open-policy-agent/vscode-opa |
| VS Code workspace settings | https://code.visualstudio.com/docs/configure/settings |

### Prepare the delivery environment

Before delivery, run the full procedure on the intended Windows image. Confirm available memory, tool-install permissions, registry access, script execution and the expected admission messages. Pin the NGINX application images to the digests observed in that rehearsal if exact repeatability is required. Keep the root and non-root Pod files identical between their before and after phases.

The core Kubernetes sequence was confirmed working before this revision. The policy templates passed strict compilation and 19 local decision cases with OPA v1.17.1. The added VS Code exercises use six supplied tests plus an extra test introduced during the editing task. Rehearse these additions on the intended Windows image before delivery.

The original source bundle is retained separately. This lab replaces its historical session log with a repeatable procedure, aligns the filenames, changes the scripts' default context to kind-opa-demo and gives both owner-label examples compliant non-root settings.
