# Muster — Concept

Muster is a free CLI from Creedworks. It makes continuous delivery for multiple applications, stacks and environments simple to manage.

It does not replace Helm, kubectl, Argo CD, Flux or GitLab CI, and it **acts only when told to** (section 11). This document is the why; [README.md](README.md) shows how to use it and [SCHEMA.md](SCHEMA.md) is the file format.

> **Define apps once, bind them per environment, and Muster produces what your CD tool needs, from minikube to production.**

Muster is **Helm-native**. Charts are used unmodified, and every layer of configuration is a plain Helm values file. Users keep their Helm skills; Muster only organises the files and puts them in the right order.

---

## 1. The problem

Helm charts already describe Kubernetes resources well. What gets messy is everything around them:

- The same application runs on different platforms (EKS, plain Kubernetes, minikube), and each needs different ingress, storage and identity settings.
- Different instances of the same app need different dependencies, for example MSSQL for one customer and PostgreSQL for another.
- A stack often spans technologies: some parts run on EKS through Helm, others on EC2, managed by Ansible. Test environments replace production integrations with mocks.
- Values files, overlays, conditionals and SOPS files are repeated and scattered across apps and environments, which makes them hard to track, maintain and compare (especially with Argo CD).
- It's hard to tell where an effective configuration value came from.
- Local environments drift away from production because they're maintained with separate scripts.

Muster uses **composition instead of repetition**: each concern is defined once and combined when Muster produces output.

## 2. Core concepts

| Concept | What it defines |
|---|---|
| **Application** | One component of a system: its Helm chart in `charts/<app>/`, app-level values (a plain values file), what the app *requires* (e.g. `db: { type: sql }`) and what it *provides* to other apps (e.g. `sanctions-api`). Some apps have no chart of their own: a service on EC2, or a database slot that each environment fills (section 4). |
| **Stack** | The apps that make up a system, listed as **members** in deploy order. An app can belong to several stacks. The stack file is the only place membership is recorded. |
| **Environment** | Where to deploy: kube context, namespace, whether a GitOps controller owns its releases (`gitops: true`) and the values every release there gets, such as the ingress class, storage class and identity (e.g. IRSA on EKS). How each stack looks in it (member modes, values) lives in the stack's folder. |
| **Provider** | A way of meeting a requirement type, such as `postgres` (a chart in `charts/`) or `mssql` (an external server). It declares the *outputs* it delivers (host, port, secret name, driver). Each app that requires it says where those outputs go in its own chart's values, and Muster adds them to that app's values. |

The application definition never changes between environments. Only the member modes, providers and values change.

### How they map onto Kubernetes and AWS

```
environment  →  one cluster (an AWS account and region) and its shared settings
  stack      →  usually one namespace; apps deployed together, in order
    app      →  one Helm release (its chart's workloads and pods), or an external or mock stand-in
```

- **An environment is one deploy target**, not a group of them: its file names one kube context, so one cluster, in one AWS account and region. Several production accounts are several environments, each with `production: true`, e.g. `prod-eu` (account A, eu-west-1) and `prod-us` (account B, us-east-1). `muster list environments --production` lists them together. The environment's `values` are what every release in that cluster shares: ingress class, storage class, identity (IRSA), image registry.
- **A stack usually gets its own namespace.** The environment decides: `namespace: "{stack}-{env}"` or `"{stack}"` gives each stack one, and a fixed name (`namespace: platform`) puts several stacks in one namespace, where release names (`<stack>-<app>`) keep them apart. The stack sets the deploy order, and `stacks/<stack>/<env>.yaml` holds everything about it in one environment.
- **An app is a Helm release, not a pod.** Its chart can run several Deployments, StatefulSets, Jobs and Services, each with as many pods as its replicas. One app in two stacks is two releases (`hello-api`, `greeter-api`). A member can also run nothing in Kubernetes: an `external` one (RDS, a service on EC2) only provides outputs, and a `mock` one runs a stand-in chart.

### Repository layout

Muster works on a repository with a fixed layout, the way Argo CD works on a Git path. Muster is pointed at the repo on disk, and the folders are the catalogue: there is no registry to keep in sync. The files are listed in [SCHEMA.md §2](SCHEMA.md#2-repository-layout).

The layout is designed to be **easy to maintain and compare**. Everything about one stack in one environment is in one file, `stacks/<stack>/<env>.yaml`. Comparing qa with prod is a diff of two files, not a search through scattered values and SOPS files.

- **An environment hosts a stack when that file exists.** No list of hosted stacks is kept anywhere else.
- Only what is shared stays outside the stack folder: the app definition and its values (one per app), the environment (one per environment) and providers.
- Which stacks an app belongs to, and where it can be deployed, are never written down. Muster derives them from the stack folders (section 7).

### Members and their modes

An environment that hosts a stack always runs **every** member of it. Nothing is ever left out. What changes per environment is how each member is present:

| Mode | Meaning | What Muster outputs |
|---|---|---|
| `helm` (default) | The app's real chart, or the provider's chart for a slot such as a database | Values, manifests, and the `helm` calls when asked |
| `external` | Runs outside Muster's reach: Ansible on EC2, RDS, an MSSQL server, a shared non-prod instance | Nothing. Its outputs come from `stacks/<stack>/<env>.externals.yaml` or the member entry (section 4) |
| `mock` | A stand-in chart from `charts/`, e.g. for production integrations in test | The same, for the mock chart |

An app with no chart of its own must be `external` or `mock`, or be filled by a provider, in every environment that hosts it. A generic stub mock chart (health checks, optionally canned responses) makes a member that a test environment doesn't care about cost one line.

### Example

```yaml
# apps/payments/app.yaml
requires:
  db:
    type: sql
    values: { host: database.host, port: database.port, secretName: database.existingSecret, driver: database.driver }
  sanctions:
    type: sanctions-api
    values: { url: integrations.sanctions.url }

# apps/orders-db/app.yaml             (a database slot; each environment picks the provider)
chart: none
provides: [{ type: sql }]

# apps/ledger-service/app.yaml        (runs on EC2, deployed by Ansible)
chart: none
provides: [{ type: http-api }]

# stacks/customer-platform/stack.yaml
members: [orders-db, sanctions-gateway, ledger-service, payments, billing]   # deploy order

# stacks/customer-platform/prod.yaml
members:
  orders-db:         { provider: postgres }          # helm: charts/postgresql
  ledger-service:    { mode: external }
  sanctions-gateway: { mode: external }
values:
  payments: { replicaCount: 6, ingress: { host: pay.example } }

# stacks/customer-platform/qa.yaml
members:
  orders-db:         { mode: external, provider: mssql, outputs: { secretName: orders-mssql } }
  ledger-service:    { mode: mock, chart: ledger-mock }
  sanctions-gateway: { mode: mock, chart: sanctions-mock }
  billing:           { mode: mock, chart: stub }
values:
  payments: { replicaCount: 1, ingress: { host: pay.qa.example } }
```

- **Requirements between members wire themselves.** `payments` requires `sql` and `sanctions-api`; `orders-db` and `sanctions-gateway` provide them, so Muster connects them in whatever mode or provider each member has. Prod gets Postgres and the external sanctions gateway; QA gets MSSQL and the mock.
- **Any database type per environment.** A database that belongs to the stack is a member without a chart. Each environment chooses the provider that fills it: Postgres in prod, MSSQL in QA. Settings that depend on the database (`database.dialect`) go in `values.<app>` in the same file that picks the provider.
- **What's outside the stack is still a member.** If `payments` needs a database the stack doesn't deploy, such as a customer's shared server, it is added as a member and made external in each environment: `partner-db: { mode: external, provider: mssql, outputs: { host: …, secretName: … } }`. Every requirement then has one kind of source, a member.
- **Release names are `<stack>-<app>`** by default, so the same app in two stacks never collides in one namespace.

*(`apiVersion` lines are left out here; see `SCHEMA.md`.)*

## 3. Configuration composition

- **Values live in three places, with one rule.** The app's values (`apps/<app>/values.yaml`, owned by the app team), the environment's (`values` in `environments/<env>.yaml`: ingress class, storage class, identity, for every release there) and the stack's environment file (`values.<app>` in `stacks/<stack>/<env>.yaml`). Anything that isn't the app's own default goes in the stack's environment file, so there is one obvious place for every value and comparing qa with prod is a diff of two files. The price is some repetition: a value shared by every environment of a stack is written in each environment file.
- **One document per release, merged with Helm's own rules**, so there's nothing new to learn. Muster merges the layers from general to specific (app, environment, stack in the environment, then wiring outputs and image versions; [SCHEMA.md §11](SCHEMA.md#layer-order)) the way Helm merges several `-f` files, and prints the result with a comment on every key naming its source. Helm reads it on stdin and applies the chart's defaults itself. Muster adds no merge rules, templating or text substitution.
- **Values are plain Helm YAML.** An app's `values.yaml` is an ordinary values file. In the stack files, each app's values sit under `values.<app>`, so one file covers the whole stack in an environment. The block is exactly what Helm would take: no Muster keys, no placeholders, no includes. Muster never rewrites a block; it only merges blocks in layer order.
- **SOPS files are passed through, never opened.** `stacks/<stack>/<env>.<app>.secrets.yaml` goes into the order as `secrets://…` for the helm-secrets plugin, which decrypts it at deploy time. There is one per app, so a release never receives another app's secrets. Secret references (`existingSecret`, External Secrets) are still preferred.
- **A mock member uses its own chart,** so the app's values file doesn't apply to it. Its values are the environment's and `values.<app>` in the stack's environment file, which always goes to whatever chart the member runs.
- **Generated values stay visible.** Outputs of members and providers (database host, secret name) appear in the printed values like any other key, marked `# wiring: …` with the member they came from. Image versions are marked with the versions file and entry they came from.
- Image versions are **deploy inputs**, not part of environment configuration. They live in a versions file per stack and environment (section 8).

## 4. Dependencies: members, providers, externals and mocks

A requirement is met by another member of the stack that provides that type (e.g. `sanctions-gateway` provides `sanctions-api`, `orders-db` provides `sql`). Muster wires it automatically, whatever mode the member runs in, including `external` for things outside Muster's reach.

Each requirement has exactly one source. `validate` rejects a requirement no member meets, and one that two members could meet. In that case the consumer names the member in the stack file:

```yaml
# stacks/customer-platform/stack.yaml
members: [orders-db, reporting-db, payments, billing]
wiring:
  payments.db: orders-db
```

Where the outputs (host, port, secret name, driver) come from depends on what meets the requirement:

| Met by | Outputs come from |
|---|---|
| Member in `helm` mode (own chart or provider chart) | The release name and the chart's naming convention, declared by the app or provider |
| Member in `mock` mode | The same, for the mock chart. A mock must produce the same outputs as the app it replaces |
| Member in `external` mode | Its provider's defaults, then `stacks/<stack>/<env>.externals.yaml` (written by whatever deploys it: an Ansible or Terraform pipeline), then the member entry's `outputs` |

```yaml
# stacks/customer-platform/prod.externals.yaml   (written by the Ansible pipeline)
outputs:
  ledger-service:
    url: https://ledger.internal.acme.example:8443
```

- Muster never queries the cluster or a cloud API for outputs, which keeps the dry run repeatable and usable offline. The externals file is a public contract: any tool can write it. `validate` fails if an external member's outputs file is missing or doesn't contain the outputs its consumers need.
- Passwords never pass through Muster. Only secret *references* do (a chart-created secret, `existingSecret`, External Secrets, SOPS).
- Database releases are **protected**: Muster never builds an uninstall for them, so its output can't remove them or their volumes (PVCs). Removing one is done by hand (see section 11). A member is protected when its app sets `protected: true`, as databases do.
- One database release can serve several apps, through several consumers wiring to the same member.
- Database charts in the stack suit dev, test, on-prem and local. Production on EKS would usually make the same member `external`, pointing at a managed service such as RDS.

## 5. One engine, two outputs

```
charts + apps + stacks + environments + providers + externals + versions
                     │
               Muster engine  →  resolved plan
                     │          (validate · releases · values · versions)
          ┌──────────┴───────────────┐
        values                deploy | uninstall
     per release              helm calls: printed, or run with --yes
          │                          │
          ▼                          ▼
   helm template → kubectl    Helm, run by a pipeline
   diff / apply, review       in a pipeline or by hand
```

Muster runs nothing unless told to. With `--yes`, `deploy`, `uninstall` and `rollback` run `helm`, and `restart` runs `kubectl`; they own the cluster credentials (through the kubeconfig) and report success or failure. Anything else is run by you or your pipeline. Which cluster a call reaches is the kube context's business (`cluster.context` in the environment file), so EKS, a data-centre cluster and minikube are the same to Muster: only the context and the environment's values differ.

| Caller | What Muster hands it |
|---|---|
| GitLab CI, Jenkins | `muster deploy -e qa --stack … --yes`: the same command as locally, one line per job. |
| Local (minikube, kind, k3d) | The same command, run by you. |
| kubectl | Plain manifests from `muster values … \| helm template …`, for `kubectl diff`, `kubectl apply --dry-run=server` or review. |

The rules for running Helm (order, protection, target, GitOps ownership) are applied once, in `muster deploy`, `uninstall`, `restart` and `rollback`, instead of in every pipeline; the [README](README.md#deploy-uninstall-restart-and-rollback) lists them. If a GitOps controller is used, `muster values … | helm template …` gives it plain manifests.

## 6. Dry run: `values --explain`

`muster values --explain` is the dry run. It takes exactly the same selection as every other command, resolves the same plan, and prints, for each release, the merged values Helm will receive, **with a comment on every key naming the file that set it**. It writes nothing.

```yaml
# 2. hello-web [helm] charts/web
# requires api ← member api (helm)
replicaCount: 1 # charts/web/values.yaml (chart default)
title: Hello (real api) # stacks/hello/local.yaml › values.web
api: # charts/web/values.yaml (chart default)
  url: http://hello-api.hello-local.svc:3000 # wiring: api ← member api (helm)
global: # charts/web/values.yaml (chart default)
  environment: local # environments/local.yaml › values
  tenant: hello # stacks/hello/local.yaml › values.web
  imagePullPolicy: IfNotPresent # environments/local.yaml › values
```

- `values --explain`, `values` and `deploy` share one plan, so the dry run always matches what will be run. `--explain` adds the chart's defaults and a header; plain `values` prints only what Helm receives.
- The chart's own `values.yaml` is the first layer, and a list that replaces another is marked on its key.
- External members are listed as "not deployed by Muster" with their outputs and the file they come from.
- SOPS files are listed as not shown: Muster never decrypts them.
- Because the output is plain YAML, comparing environments is a diff of two `values --explain` outputs.
- Limitation: it can't reach into chart templates, so it shows what Helm receives, not what the chart does with it.

## 7. Deployment scope

Every command takes the same form, `muster <command> [app] -e <env> --stack <stack>`, and covers two kinds of deployment: a whole stack, or one app in a stack.

```bash
muster releases -e local --stack customer-platform                  # a whole stack: releases and parameters, in order
muster values   payments -e qa --stack customer-platform            # an app in a stack: the values for helm -f -
muster values   payments -e qa --stack customer-platform --explain  # the same, as a dry run
muster deploy   -e qa --stack customer-platform                     # the helm calls; --yes runs them
```

Each deployment has an explicit identity, **stack + application + environment**, so an app in two stacks becomes two independent releases (`<stack>-<app>`). `validate` rejects two releases with the same name in one namespace.

### Matrix deployment

Within an environment, the possible deployments form a matrix: **apps × stacks**. Muster builds it from two facts, each recorded in exactly one place:

| Fact | Recorded in |
|---|---|
| Which apps are members of a stack, and in what order | `stacks/<stack>/stack.yaml` |
| Which environments host a stack, and each member's mode there | `stacks/<stack>/<env>.yaml` (the file existing means the environment hosts the stack) |
| Which stacks an app is in; where it can be deployed | Derived, never written down |

The matrix is **complete**: every environment runs every member of every stack it hosts, as `helm`, `external` or `mock`. Nothing is omitted.

Every command selects from it the same way: a whole stack, or one app into one or more stacks ([README](README.md#commands)). Each run covers one environment. Moving an image version between environments is `muster versions promote` (section 8).

**Expansion.** Muster expands the selection into individual **cells**, each one stack + app in the environment. Every cell is resolved on its own, with its own mode, provider and values.

- **The stack is always named**, with `--stack` or `--all-stacks`, even when only one stack could match. A command then means the same thing after a stack is added.
- If an app isn't in a named stack, or a named stack isn't hosted by the environment, Muster says so, lists the valid options, and stops. It never silently skips.
- Selecting an app produces **only that app**; the members it requires are assumed present. To bring up everything, select the whole stack.

**Ordering.** The stack and the charts decide the order; Muster doesn't infer it.

- **Whole stack:** members are deployed in the order the stack lists them. Inside a chart, Helm orders its subcharts. `validate` warns when a member is listed before a member it requires.
- **An app into several stacks:** the cells are independent, so they're marked as able to run in parallel.
- **External members** get no `helm` call, only a `skip` with the reason, but keep their place in the order.
- `deploy --yes` stops at the first failing call. Parallelism, retries and reporting which cells succeeded belong to the pipeline.

**Output.** Everything goes to stdout, and the caller saves what it needs (in a pipeline, usually a temp folder). `muster releases --json` is data only and never contains a command.

**Validation.** `muster validate` with no selection resolves the whole matrix: every hosted stack in every environment. It checks that every member resolves to one mode, that apps without a chart are never in plain `helm` mode, that every requirement is met by exactly one member, that external outputs files exist, and that release names don't collide. A change to an app's or an environment's values is checked against every cell it touches.

## 8. Image versions

Image versions change far more often than configuration, and shipping one should never mean editing values files. They live in their own file, one per stack and environment, which only `muster versions set` and `promote` change. The file's rules are in [SCHEMA.md §10](SCHEMA.md#stacksstackenvversionsyaml) and its use in the [README](README.md#versions).

- **Promoting is copying.** The file sits beside the stack's other files for that environment, so promoting is copying entries from one environment's file to the next.
- **The commit is the record.** Every later deploy uses the file until it changes, so it is committed, and the commit records what shipped where, who shipped it and when. The file therefore holds only versions; in a GitOps flow, the commit is the deploy. Muster itself never commits (section 11).
- **A gate, not an updater.** Each environment says which tags it takes, and Muster checks every tag wherever it comes from (the versions file, a values file or the chart's default), so a feature build can't reach production through any pipeline or laptop. Muster never picks a tag or asks a registry.
- **The last layer before secrets,** so a version beats any tag in the values files. Without one, an image keeps the tag its values files or the chart give.
- **Only an app running its own chart** has versions: never a mock, an external member or a provider's chart.

## 9. Local development

- `local` is just another environment, with the minikube context and minikube's values (e.g. `imagePullPolicy: IfNotPresent`).
- `muster deploy -e local --stack <stack> --yes` deploys the full stack, including databases, from the same app definitions as production, with the same calls a pipeline runs.
- Images need no registry: build them into the cluster (`minikube image build -t api:v2 src/api`), then `muster versions set api=v2 -e local --stack <stack> --write` and deploy.
- Members that are `external` in production (e.g. services on EC2) are usually `mock` locally, so the whole stack runs on one machine.
- `muster values … | helm template … | kubectl diff -f -` shows what a change would do to the running stack before deploying it.

Testing is layered: unit tests, a comparison of the values merge for every example release against `helm template`, and a fuzz test of the merge, all with no cluster → integration tests on minikube, kind or k3d → real environments (EKS) through GitLab or Jenkins.

## 10. Design rules

1. **Compose; don't replace.** Helm owns charts. Helm, kubectl, Argo CD, Flux and GitLab own delivery. Muster owns composition.
2. **Muster prints, and acts only when told to.** It provides what it knows (releases, order, modes, targets, wiring, protection) and what it generates (values), on stdout. `deploy`, `uninstall`, `restart` and `rollback` print the `helm` or `kubectl` calls and run them only with `--yes`, so the rules for running them (skip external members and GitOps environments, never uninstall a protected release, name the kube context and namespace) are applied once, in tested code, not in every pipeline. It writes no file except a stack's image versions file, and that only when asked (`muster versions set|promote --write`). Its only inputs are the repository and the command line: no environment variables.
3. **Helm-native, nothing to re-learn.** Charts are unmodified, values are plain Helm YAML (in an app's values file, or under `values` in an environment or stack file), and values merge with Helm's own rules. Every output can be reproduced with a plain `helm` command.
4. **Muster never holds credentials.** It runs `helm` or `kubectl` only with `--yes`, and they use the kubeconfig; Muster never talks to a cluster itself or commits to Git. Without `--yes` it has no consequences (section 11).
5. **Output must be repeatable and must not touch the cluster.** The same files always give the same output; Muster renders nothing itself.
6. **No secrets in output or Git.** Only references.
7. **Few concepts, strict validation.** Resist exceptions; if the model gets complicated, Muster has only moved the complexity.
8. **The engine is a library.** The CLI is a thin layer over it, so a future controller or other integration can call the same Go packages.
9. **Easy to adopt and to remove.** Muster can be adopted one app at a time and dropped without migrating anything: saved values files and the `helm` calls it printed keep working without it.
10. **One simple command form.** `muster <command> [app] -e <env> --stack <stack>`, with the stack always named. Nothing is inferred that could change meaning when the repository grows.

## 11. Safety model

**Without `--yes`, Muster has no consequences.** Whatever anyone runs, with any config, flags or input, nothing changes except a versions file it was explicitly asked to write. Consequences appear only with `--yes` on `deploy`, `uninstall`, `restart` or `rollback`, which run helm or kubectl, or when another tool acts on Muster's output.

Muster's job is to make every call it runs, or prints, safe to run.

### Invariants that make "no consequences" true

These are hard requirements; breaking one breaks the guarantee.

| Invariant | What it rules out |
|---|---|
| No cluster access | Muster opens no connection to a cluster and holds no credentials; with `--yes` it runs the `helm` or `kubectl` binary, which uses the kubeconfig |
| No Git writes | Muster edits files in the working tree; it never commits, pushes or opens merge requests |
| Writes only when told | Everything goes to stdout. The one file Muster writes is a stack's versions file, with `--write`, replaced atomically |
| No execution from config | Config and providers are declarative data. No hooks, shell commands or executable plugins, so running Muster never runs someone else's code |
| No network | Muster never fetches anything: charts are in the repository, or in a registry that helm reads at deploy time with its own login |
| Nothing runs by default | Only `deploy`, `uninstall`, `restart` and `rollback` print `helm` or `kubectl` calls, and they run them only with `--yes`. `releases` and `values` are data |
| No secrets | Only secret references are read or written (design rule 5) |

### Where pairing creates consequences, and what Muster does about it

The tool that acts owns the consequence, but Muster's output decides what that tool does. Muster therefore makes dangerous output hard to produce by accident:

| Risk once paired | Example | What Muster does |
|---|---|---|
| Deletion by omission | A member disappears after a rename or bad merge, and a teardown or cleanup removes its release, database included | Environments can't omit members, so a cell only disappears when a stack's member list changes or a `stacks/<stack>/<env>.yaml` file is deleted. `commands uninstall` never builds a call for a protected release. |
| Mode change | A member switches from `helm` to `external` or `mock`, and its real release is pruned | Modes are explicit in the stack's environment file, so the change is a visible line in review; `releases` shows every member's mode. (A classified diff for CI is on the roadmap.) |
| Mock in production | A copy-paste puts `sanctions-mock` into a production environment | `validate` rejects `mock` mode in environments marked as production |
| Stale external outputs | The externals file points at an old EC2 host after Ansible moved the service | The file is the contract: `validate` checks it exists and is complete, and `values --explain` shows it as the source. Keeping it current belongs to the pipeline that deploys the external member |
| Wrong target | Commands run against whatever kube-context is active, possibly production | Every call names `--kube-context` and `--namespace` from the environment file, so nothing depends on the active context |
| Accidental execution | A saved output or a shell-history line is replayed against an environment | `deploy`, `uninstall`, `restart` and `rollback` print unless given `--yes`, and an uninstall in a production environment also needs `--confirm <env>`. A protected release never gets an uninstall at all |
| Empty values | `muster values … \| helm …` runs Helm with no values when Muster fails | `deploy --yes` resolves every release before it runs anything, and passes each release's values to helm itself |
| Wrong external source | `payments.db` points at another customer's secret | `values` names the member every wired value came from, so review shows it. (Not checked automatically yet; see the roadmap.) |
| Silent merge loss | A list replaced or a key deleted by `null` in a lower layer | `values --explain` names the layer that set every key, and marks a replaced list on its key |
| Version change that deploys | `muster versions set` edits a file and CI auto-deploys the commit | Without `--write` it only prints the new file; whether a commit deploys is the pipeline's decision |

## 12. Scope

What Muster does today is in the [README](README.md#commands).
