# Muster — MVP schema

Status: **draft v1alpha1**. This is the contract for Muster's files and rules: what each file holds, how a stack resolves, and what `validate` checks. Why it is this way is in [CONCEPT.md](CONCEPT.md), how to use it in [README.md](README.md). Decisions still open are listed in section 13.

**Design goal: a repo people can maintain and compare at a glance.** Everything about one stack in one environment lives in one file, inside the stack's folder. Comparing qa with prod is a diff of two files side by side, not a hunt through scattered values and SOPS files.

---

## 1. General rules

- **Every Muster file starts with `apiVersion: muster/v1alpha1`.** Its kind comes from its name and place (`app.yaml`, `stack.yaml`, `<env>.yaml` …), so there is no `kind:` field.
- **Unknown fields are errors.** A typo such as `memebers:` fails `validate` rather than being ignored.
- **Values are plain Helm YAML.** Under a `values:` key, or in an app's `values.yaml`, they are exactly what Helm would take: no Muster keys, no placeholders, no includes. Muster merges the layers with Helm's own rules into one document per release and prints it (section 11).
- **Names** of apps, stacks, environments, providers and types are DNS-1123 labels: lowercase letters, digits and `-`, starting with a letter, at most 40 characters. The release name `<stack>-<app>`, with the environment's `release.prefix` and `release.suffix` if it sets them, must fit Helm's 53-character limit; `validate` checks it.
- **Paths** are relative to the repository root and must stay inside it.
- **Charts** are named in three ways, wherever a chart is named (an app's `chart`, a provider's, a mock member's):

  | Written as | The chart | Its version |
  |---|---|---|
  | `payments` | The folder `charts/payments/` | The one in the folder |
  | `oci://<registry>/<path>/<chart>`, e.g. `oci://123456789012.dkr.ecr.eu-west-1.amazonaws.com/charts/payments` | In an OCI registry, such as ECR | Pinned (below) |
  | `https://<repository>/<chart>`, e.g. `https://charts.example.com/stable/postgresql` | In a classic chart repository: its URL, then the chart's name | Pinned (below) |

  A chart in a registry is pinned to an exact version (`1.4.2`, `1.5.0-rc.1`; no ranges), so the same files always deploy the same chart: an app's own chart in its stack's versions file, as `<app>.chart` (section 10), so it moves between environments with `versions set` and `promote`; a provider's or a mock's in `chartVersion` beside it. **Muster never fetches a chart:** helm does, at deploy time, with the credentials it has (`helm registry login`, `helm repo add`), and the reference never holds credentials. So Muster can't read a remote chart's defaults: `values --explain` leaves them out, and each image of an app whose chart is in a registry must get its tag from the versions file or the values (V007).
- **Placeholders.** A small fixed set may appear in output templates and in `namespace` only: `{env}`, `{stack}`, `{app}`, `{release}`, `{namespace}`. There are no expressions, functions or conditionals, and never any in values.

## 2. Repository layout

```
muster.yaml                                # root marker
charts/<chart>/                           # unmodified Helm charts in the repository: apps, mocks, provider charts (or name one in a registry: section 1)

apps/<app>/app.yaml                       # what the app needs and provides
apps/<app>/values.yaml                    # the app's values, everywhere (plain Helm values file)

stacks/<stack>/stack.yaml                 # members in deploy order, wiring
stacks/<stack>/<env>.yaml                 # this stack in <env>: member modes, each member's values
stacks/<stack>/<env>.externals.yaml       # outputs of external members in <env>, written by other tools
stacks/<stack>/<env>.versions.yaml        # image versions to deploy in <env>, written by muster versions --write
stacks/<stack>/<env>.<app>.secrets.yaml   # SOPS-encrypted values for one app in <env>

environments/<env>.yaml                   # kube context, namespace, Helm settings, values for every release in <env>

providers/<provider>/provider.yaml        # optional: user-defined providers
providers/<provider>/values.yaml          # optional: defaults for a provider's chart
```

A stack folder in practice:

```
stacks/customer-platform/
  stack.yaml
  local.yaml
  qa.yaml
  qa.externals.yaml
  qa.versions.yaml
  prod.yaml
  prod.externals.yaml
  prod.versions.yaml
  prod.payments.secrets.yaml
```

- **An environment hosts a stack when `stacks/<stack>/<env>.yaml` exists.** No list of stacks is kept anywhere else. A file containing only `apiVersion` means "host it with all defaults".
- **Discovery is by folder.** An app exists if `apps/<app>/app.yaml` exists, a stack if `stacks/<stack>/stack.yaml` exists, an environment if `environments/<env>.yaml` exists.
- **A stack file for an unknown environment is an error.** `stacks/customer-platform/qq.yaml` fails `validate` with "no environment `qq`; environments are: local, qa, prod".
- **What stays outside the stack folder, and why:** the app definition and its values (owned by the app team, shared by every stack), the environment (shared by every stack in it), and providers (shared by everything).
- **Values live in three places**: the app (`apps/<app>/values.yaml`), the environment (`values` in `environments/<env>.yaml`) and the stack in the environment (`values.<app>` in `stacks/<stack>/<env>.yaml`). Anything that isn't the app's own default goes in the stack's environment file (section 11).

## 3. Root: `muster.yaml`

```yaml
apiVersion: muster/v1alpha1
```

No other fields in v1alpha1. It marks the repository root, so Muster can run from any subfolder. `--repo` overrides it.

## 4. Types

A type is the contract between something that requires a thing and whatever provides it: a name that apps agree on, such as `sql` or `sanctions-api`. There are no type files and no built-in types. A type's contract is whatever its consumers map: within a stack and environment, the source of a requirement must deliver every output that the requiring app lists in `requires.<r>.values`. Types say nothing about state: an app whose data must outlive a teardown sets `protected: true` (section 5).

Types are checked per stack: two apps can spell an output differently (`url` and `endpoint`), and validation only notices when they share a source. If that becomes a problem, type files can be added later (section 13).

## 5. Apps: `apps/<app>/app.yaml`

Everything about the app that is the same in every stack and environment.

```yaml
apiVersion: muster/v1alpha1
chart: payments              # folder in charts/, or in a registry: oci://… or https://… (section 1); default: the app's name
requires:
  db:
    type: sql
    values:                  # where each output goes in this app's chart
      host:       database.host
      port:       database.port
      database:   database.name
      secretName: database.existingSecret
      driver:     database.driver
  sanctions:
    type: sanctions-api
    values:
      url: integrations.sanctions.url
```

```yaml
# apps/sanctions-gateway/app.yaml
apiVersion: muster/v1alpha1
provides:
  - type: sanctions-api
    outputs:
      url: "http://{release}.{namespace}.svc:8080"
```

```yaml
# apps/orders-db/app.yaml — a slot: each environment chooses the provider that fills it
apiVersion: muster/v1alpha1
chart: none
provides:
  - type: sql
protected: true              # a database: never uninstalled
```

```yaml
# apps/ledger-service/app.yaml — runs on EC2, never deployed by Muster
apiVersion: muster/v1alpha1
chart: none
provides:
  - type: http-api
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `chart` | string | the app's name | Folder under `charts/`, a chart in a registry (`oci://…`, `https://…`; its version is in each versions file, section 10), or `none` for an app with no chart of its own |
| `requires` | map of name → requirement | `{}` | What the app needs. Names are camelCase |
| `requires.<r>.type` | type name | — | The type it needs (section 4) |
| `requires.<r>.values` | map of output → values path | — | Where each output goes in **this app's** chart values (dotted path). It also defines the outputs the source must deliver |
| `provides` | list of `{ type, outputs }` | `[]` | Types this app delivers to other members |
| `provides[].outputs` | map of output → string | `{}` | How each output is built when the app runs as `helm` or `mock`, with placeholders. An output a consumer maps must be given (X005) |
| `protected` | bool | `false` | A protected release never gets an `uninstall`. Set it on databases and anything else whose data must outlive a teardown |
| `images` | map of image name → values path | none | The images the app's chart runs, and where each one's tag goes. Versions files (section 10) fill them. Name them when the chart runs several images, such as an init container or a sidecar (`app: image.tag`, `migrator: migrations.image.tag`), or takes its tag elsewhere. A values path is dotted map keys, so the chart must take each tag at a map path, not inside a list. `chart` is not an image name: it holds the chart's version |

`apps/<app>/values.yaml` is the app's values file, applied everywhere. It stays a separate plain file because it's the one the app team already has, and it works with `helm` on its own. It is the only values file in the app's folder: values for the app in one environment go in each stack's environment file, under `values.<app>` (section 8).

## 6. Providers: `providers/<provider>/provider.yaml`

A reusable way to fill a slot app (a `chart: none` member): a chart, or an external service of a known shape.

```yaml
# providers/postgres/provider.yaml
apiVersion: muster/v1alpha1
type: sql
chart: postgresql            # folder in charts/, or in a registry; omit for an external-only provider
outputs:
  host:       "{release}-postgresql.{namespace}.svc.cluster.local"
  port:       "5432"
  database:   "app"
  secretName: "{release}-postgresql"
  secretKey:  "password"
  driver:     "postgres"
```

```yaml
# providers/mssql/provider.yaml: no chart, so its members are external
apiVersion: muster/v1alpha1
type: sql
outputs:
  port:      "1433"
  driver:    "sqlserver"
  secretKey: "password"
# host, database, secretName come from <env>.externals.yaml or the member entry
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `type` | type name | — | The type this provider delivers |
| `chart` | string | none | Folder under `charts/` or a chart in a registry (section 1), used when the member is `helm`. Without one, members it fills must be `mode: external` |
| `chartVersion` | string | — | Required for a chart in a registry, and only then: its exact version |
| `outputs` | map of output → string | `{}` | Constant or placeholder outputs. For external use these are defaults that the externals file and the member entry override |

Muster has no built-in providers: what you see in `providers/` is all there is. `postgres` above needs `charts/postgresql/` in the repo (e.g. `helm pull --untar`), or names the chart in a registry:

```yaml
chart: oci://registry-1.docker.io/bitnamicharts/postgresql
chartVersion: 15.5.0
```

## 7. Stacks: `stacks/<stack>/stack.yaml`

What the stack is: its members and how they connect. It holds no values; those are per environment (section 8).

```yaml
apiVersion: muster/v1alpha1
members:                     # deploy order
  - orders-db
  - sanctions-gateway
  - ledger-service
  - payments
  - billing
wiring:                      # only when more than one member could meet a requirement
  payments.db: orders-db
```

| Field | Type | Meaning |
|---|---|---|
| `members` | list of app names | The stack's apps, in deploy order. No duplicates |
| `wiring` | map of `<app>.<requirement>` → member | Picks the member that meets a requirement when more than one provides its type |

## 8. Stack in an environment: `stacks/<stack>/<env>.yaml`

**The main file people edit.** Everything that makes this stack different in this environment.

```yaml
# stacks/customer-platform/qa.yaml
apiVersion: muster/v1alpha1
members:
  orders-db:         { mode: external, provider: mssql, outputs: { secretName: orders-mssql } }
  ledger-service:    { mode: external }
  sanctions-gateway: { mode: mock, chart: sanctions-mock }
  billing:           { mode: mock, chart: stub }
values:
  sanctions-gateway:                  # the mock's values
    latencyMs: 50
  payments:
    replicaCount: 1
    ingress: { enabled: true, host: pay.qa.example }
    logLevel: debug
    global: { tenant: customer-platform }
```

```yaml
# stacks/customer-platform/prod.yaml
apiVersion: muster/v1alpha1
members:
  orders-db:         { provider: postgres }
  ledger-service:    { mode: external }
  sanctions-gateway: { mode: external }
values:
  orders-db:                          # the postgresql chart's values
    primary: { persistence: { size: 200Gi } }
  payments:
    replicaCount: 6
    ingress: { enabled: true, host: pay.example }
    logLevel: warn
    global: { tenant: customer-platform }
  billing:
    schedule: "0 2 * * *"
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `disabled` / `reason` | bool / string | `false` | `disabled: true` turns the stack off for changes in this environment; `reason` says why, and is required with it ([Disabling](README.md#disabling-an-environment-a-stack-or-an-app)) |
| `members.<app>` | member entry | `helm` with the app's chart | How a member is present in this environment |
| `values.<app>` | values | — | Values for whatever chart the member runs here: its own, the mock or the provider's. Everything about it here that isn't a default (replicas, hosts, resources, log level). An error for an `external` member, which runs no chart |

**Member entry**

| Field | Meaning |
|---|---|
| `mode` | `helm`, `external` or `mock`. Default `helm`. A provider never changes it |
| `provider` | Only for `chart: none` apps: the provider filling the slot. Its type must match the app's `provides` |
| `chart` | Only with `mode: mock` (an error otherwise): the mock's folder under `charts/` or a chart in a registry (section 1), e.g. a generic stub chart that answers health checks |
| `chartVersion` | Only with a `chart` in a registry, and required then: its exact version |
| `outputs` | Output overrides, highest precedence. Mainly for `external` |
| `disabled` / `reason` | `disabled: true` turns this member off for changes in this environment; `reason` says why, and is required with it ([Disabling](README.md#disabling-an-environment-a-stack-or-an-app)) |

**Every requirement is met by a member.** Something outside Muster that an app needs, such as a shared database, is added to the stack as a member with `mode: external`, optionally with a provider for default outputs. It gets no helm call, and its outputs come from the entry, the provider and `<env>.externals.yaml`.

## 9. Environment: `environments/<env>.yaml`

Only what every stack in the environment shares: where it is and how it's deployed.

```yaml
apiVersion: muster/v1alpha1
gitops: false                         # true: a GitOps controller owns the releases
production: false
versions:
  tags: '.+'                          # the image tags it takes, matched in full
cluster:
  context: qa-cluster                 # --kube-context on every helm call: it picks the cluster
namespace: "{stack}"                  # one namespace per stack, or a fixed name
release:                              # optional: added to every release name in qa
  prefix: ""
  suffix: "-qa"                       # hello-web becomes hello-web-qa
helm:
  wait: true
  timeout: 10m
  createNamespace: true
values:                               # every release in qa
  global:
    environment: qa
    ingressClassName: nginx
    storageClassName: standard
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `values` | values | — | Every release in the environment gets them, mocks and provider charts included: platform settings such as the ingress class, storage class or image pull policy. Keep them under `global:`, which every chart accepts |
| `gitops` | bool | `false` | A GitOps controller owns the releases: `muster deploy`, `uninstall`, `restart` and `rollback` make no call for them, and `releases` reports `gitops: true` so other callers skip them too |
| `production` | bool | `false` | `mock` members are an error when `true`; `muster uninstall --yes` also needs `--confirm <env>` |
| `disabled` / `reason` | bool / string | `false` | `disabled: true` turns the whole environment off for changes; `reason` says why, and is required with it ([Disabling](README.md#disabling-an-environment-a-stack-or-an-app)) |
| `versions.tags` | regular expression | any tag | The image tags the environment takes, matched in full, e.g. `'[0-9]+\.[0-9]+\.[0-9]+'` for release tags only. Checked for every image of an app's own chart, wherever its tag comes from: the versions file, a values file or the chart's default (V004) |
| `cluster.context` | string | — | Required unless `gitops` is `true` |
| `namespace` | string | — | May use `{stack}` and `{env}` |
| `release.prefix` / `release.suffix` | string / string | `""` / `""` | Added to every release name in the environment, like a Kustomize overlay's `namePrefix` and `nameSuffix`: `<prefix><stack>-<app><suffix>`. Lowercase letters, digits and `-`; a prefix doesn't start with `-` and a suffix doesn't end with it (S002). `{release}` in outputs, and so the wiring, uses the full name. Changing either renames every release: the next deploy installs new releases beside the old ones, which Muster doesn't remove, so uninstall the old ones first, and move a protected release's data by hand (CONCEPT.md section 11) |
| `helm.wait` / `helm.timeout` / `helm.createNamespace` | bool / duration / bool | `true` / `5m` / `false` | `--wait` and `--timeout` on every helm call; `--create-namespace` on deploys. With `wait`, `muster restart` waits for each restart with `kubectl rollout status --timeout` |

## 10. Externals and secrets

### `stacks/<stack>/<env>.externals.yaml`

Written by whatever deploys the external members (an Ansible or Terraform pipeline). One file per stack and environment, keyed by member:

```yaml
apiVersion: muster/v1alpha1
writtenBy: ansible/ledger-deploy      # optional, for people reading the file
writtenAt: 2026-10-19T08:12:00Z       # optional
outputs:
  ledger-service:
    url: https://ledger.internal.acme.example:8443
  orders-db:
    host: sql01.qa.internal
    database: orders
```

It's kept separate from `<env>.yaml` so machines write one file and people edit the other. The file is optional: an external member whose outputs all come from its provider and member entry doesn't need it. Unknown member names are errors, and a missing output a consumer needs is caught by X005, as is an external member with no outputs from any source.

### `stacks/<stack>/<env>.versions.yaml`

The image versions to deploy for a stack in one environment, and the versions of apps' charts that are in a registry. CI or a developer changes it with `muster versions`, never by hand:

```bash
muster versions set payments=1.4.2 --env qa --stack customer-platform --write
muster versions promote --from qa --env prod --stack customer-platform --write # what qa runs, into prod
```

```yaml
apiVersion: muster/v1alpha1
versions:
  payments:
    app: 1.4.2
    migrator: 1.4.2
    chart: 1.4.0               # payments' chart is in a registry (app.yaml: chart: oci://…)
  billing:
    app: latest
```

- **Keyed by app, then image** (the app's `images`). In `set`, the image can be left out when the app has only one, or has one named `app`, which it then means: `payments=1.4.2` is `payments.app=1.4.2`. Name the others: `payments.migrator=1.4.2`.
- **A version is a tag** (`1.4.2`, `latest`), which the chart gets at the image's tag path. A digest may follow, `1.4.2@sha256:…`: it goes to the chart as written, and Muster doesn't check it. The environment's `versions.tags` says which tags it takes (§9). Muster never asks a registry.
- **It is optional, per app and per image.** An app or image it leaves out gets whatever tag the values files give, or the chart's default.
- **It persists.** Every later deploy of the stack in that environment uses it, until it is changed. Commit it, so the next pipeline deploys what the last one did. Git records who changed it and when, so the file holds only versions: writing the same versions again leaves it unchanged.
- **`chart` is the version of the app's chart, when it is in a registry** (section 1), set with `versions set payments.chart=1.4.0` and copied by `promote` like a tag. Such an app needs it in every environment that hosts it (V006); an app whose chart is in `charts/` has none. It is an exact chart version, and `versions.tags` doesn't apply to it.
- **It only applies to an app running its own chart** that names `images` or whose chart is in a registry: never to a mock or to a provider's chart filling a slot. `muster list … --versioned` gives where that holds.
- `set` and `promote` print the new file; with `--write` they replace it atomically.

### `stacks/<stack>/<env>.<app>.secrets.yaml`

A SOPS-encrypted Helm values file for one app in one environment, as used with the helm-secrets plugin.

- **Muster never decrypts it.** It checks the file exists and has SOPS metadata, puts it in the layer order, and emits it as `-f secrets://stacks/customer-platform/prod.payments.secrets.yaml`. helm-secrets decrypts it at deploy time, so Muster stays in line with "no secrets" (`CONCEPT.md` §10).
- **It's one file per app** because each release must only receive its own secrets. One shared file would put every app's secrets into every Helm release.
- **References are still preferred.** Where a chart supports `existingSecret` or External Secrets, a secret *name* in `values:` or `outputs:` avoids SOPS files altogether.

## 11. Resolution

Muster resolves one whole stack in one environment at a time, in one pass, always in the same order. Every file is read once, every cell is complete when resolution ends, and a command then prints the cells it was asked for (one app, or all of them).

1. **Load** the stack's Muster files: environment, stack, stack in environment, externals and versions.
2. **Check** them (section 12, structure rules).
3. **Resolve each member** in member order: its mode, chart and outputs (placeholders filled in: `{release}` is `<prefix><stack>-<app><suffix>`, with the environment's `release.prefix` and `release.suffix`, `{namespace}` the environment's namespace for the stack), and which images it has.

   | `mode` (default `helm`) | Chart | Outputs, lowest → highest precedence |
   |---|---|---|
   | `helm` | app chart, or the provider's chart | app `provides[].outputs`, or provider `outputs` → entry `outputs` |
   | `mock` | entry `chart` | app `provides[].outputs` (same release name) → entry `outputs` |
   | `external` | none | provider `outputs` → `<env>.externals.yaml` → entry `outputs` |

4. **Check the versions file** against those members and images.
5. **Wire requirements.** For each requirement of each `helm` or `mock` cell: the member of the same stack providing the type, through `wiring` if more than one does. Exactly one source; a requirement no member meets is an error (add an external member for it). Resolution stops here if anything so far is an error.
6. **Build each deployed cell's values**: its layers in order (below), merged into the values Helm gets, and merged over the chart's defaults for `values --explain`.
7. **Print** the selected cells. `muster deploy`, `uninstall`, `restart` and `rollback` build a call for each `helm` and `mock` cell, and run them with `--yes`; external cells, and every cell in a `gitops` environment, keep their place in the order with a reason instead.

### Layer order

| # | Layer | App's own chart | Provider chart filling a slot | Mock |
|---|---|---|---|---|
| 0 | Chart defaults | chart's `values.yaml` (applied by Helm) | same | same |
| 1 | App | `apps/<app>/values.yaml` | `providers/<prov>/values.yaml` | — |
| 2 | Environment | `environments/<env>.yaml` → `values` | same | same |
| 3 | Stack in environment | `stacks/<stack>/<env>.yaml` → `values.<app>` | same | same |
| 4 | Outputs | generated from wiring | same | same |
| 5 | Versions | `<env>.versions.yaml` → `versions.<app>.<image>`, at each image's tag path | — | — |
| 6 | Secrets | `<env>.<app>.secrets.yaml` (via `secrets://`) | same | — |

**The rule: general to specific, and the stack's environment file has the last word.** The app's values hold its defaults, the environment adds what every release there needs, and the stack's environment file sets everything else about the app in that stack and environment. A `replicaCount` in `stacks/customer-platform/prod.yaml` wins over one in `apps/payments/values.yaml`. Only outputs, versions and secrets come later.

**Muster merges, Helm applies chart defaults.** Layers 1 to 5 are merged into one document the way Helm merges several `-f` files: maps merge, scalars and lists replace, and an explicit `null` is kept so Helm still deletes that key from the chart's defaults. Keys are compared the way Helm reads them (YAML 1.1, so `on`, `yes` and `true` are one key and `"on"` is another), and anchors, aliases and `<<` merge keys are resolved first. Helm receives the document on stdin (`-f -`) and applies the chart's `values.yaml` itself. A test renders every example release through `helm template` both ways (the layers as separate files, and Muster's document) and requires identical values. Secrets come last, as `-f secrets://…` after stdin, because Muster never opens them. Wiring outputs and then image versions therefore sit just before secrets, so a version from the versions file beats any tag in the values files.

### Output

Every command prints to stdout; what Muster may and may not do is its safety model ([CONCEPT.md §11](CONCEPT.md#11-safety-model)). The commands and their output are described in the [README](README.md#commands). The JSON of `releases --json` is a public contract: one object per member, external members included and marked by `mode`. `order` is the position in the stack's member list. A caller that runs other operations itself (restart, rollback) skips `mode: external` and `gitops: true`; `deploy` and `uninstall` apply these rules, and never uninstall `protected: true`.

## 12. Validation

Errors stop every command except `validate`. `validate` reports every problem, not just the first. Each message names the file, the field and, where useful, the valid options.

**Structure**

| Code | Rule |
|---|---|
| S001 | Every Muster file has `apiVersion: muster/v1alpha1`, no unknown fields, and the fields it requires (an environment's `namespace`, and `cluster.context` unless `gitops`; a path for every image; a `reason` with `disabled: true`, and only then) |
| S002 | Names of apps, stacks, environments, images and types are valid DNS-1123 labels of at most 40 characters; no image is named `chart` |
| S003 | Every referenced chart folder exists and contains `Chart.yaml` |
| S004 | Every referenced environment, stack, app and provider exists |
| S005 | Every `stacks/<stack>/<env>*.yaml` file names an existing environment and, for secrets files, a member of the stack; `apps/<app>/` holds only `app.yaml` and `values.yaml` |
| S006 | Every `*.secrets.yaml` file has SOPS metadata (checked without decrypting) |
| S007 | A chart in a registry is `oci://<registry>/<path>/<chart>` or `https://<repository>/<chart>`, without credentials; a provider's or mock's has a `chartVersion` that is an exact version, and a chart in `charts/` has none |

**Model**

| Code | Rule |
|---|---|
| M003 | A `chart: none` app has at least one `provides` entry |
| M004 | A stack lists each member once |
| M005 | Warning: a member is listed before a member it requires |

**Matrix** (every hosted stack in every environment)

| Code | Rule |
|---|---|
| X001 | A `chart: none` member in `helm` mode has a provider with a chart; otherwise it is `external` or `mock` |
| X002 | `provider` is used only on `chart: none` apps and never with `mock`, its type matches the app's `provides`, and a provider without a chart is used only with `mode: external` |
| X003 | `mock` needs `chart`; `mock` is not allowed when the environment has `production: true` |
| X004 | Every requirement of a `helm` or `mock` cell has exactly one source: a member of the same stack, through `wiring` if more than one provides its type |
| X005 | Every source delivers every output its consumers map: from `provides[].outputs`, provider, externals file and entry combined |
| X006 | Release names are at most 53 characters, and unique per namespace across the stacks an environment hosts (stack `a-b` with app `c` and stack `a` with app `b-c` both make `a-b-c`) |
| X007 | Every key under `members`, `values`, `wiring` and an externals file's `outputs` names a member; `values.<app>` is not set for an `external` member; a member entry's `chart` is only set with `mode: mock` |

**Versions** (`<env>.versions.yaml`, and the tags an environment takes)

| Code | Rule |
|---|---|
| V001 | Every app in the file is a member of the stack running its own chart (not `mock`, `external` or a provider's chart) |
| V002 | Every image is one of the app's `images` |
| V003 | Every version is a valid image tag, optionally followed by `@<digest>`, which is not checked |
| V004 | Every image tag an environment deploys (the part before any `@`) matches its `versions.tags`, whether it comes from the versions file, a values file or the chart's default. `versions set` and `promote` refuse such a tag, and are how to replace one |
| V005 | Warning: the environment's `values` or the stack's `values.<app>` for the same environment also set an image's tag path. The versions file wins, so remove one. A tag in `apps/<app>/values.yaml` is the fallback and is not reported |
| V006 | An app whose own chart is in a registry has `<app>.chart` in the versions file of every environment that hosts it, an exact chart version; an app whose chart is in `charts/` has none |
| V007 | Each image of an app whose chart is in a registry gets its tag from the versions file or a values file, never the chart's default, which Muster can't read |

**Disabled** (`disabled: true`)

| Code | Rule |
|---|---|
| D001 | Nothing changes what is disabled: `deploy`, `uninstall`, `restart`, `rollback`, `versions set` and `promote` refuse a disabled environment, a disabled stack named with `--stack`, or a disabled app named in one, and skip what is disabled in a wider selection |

**Selection**

| Code | Rule |
|---|---|
| L001 | The environment hosts every named stack; the error lists the stacks it does host |
| L002 | The app is a member of every named stack; the error lists the stack's members |
| L003 | Every command names its stacks with `--stack` or `--all-stacks`; an app with `--all-stacks` is in at least one hosted stack |

## 13. Open decisions

1. **Placeholders in metadata.** Output templates such as `"{release}-postgresql.{namespace}.svc.cluster.local"` are the only text substitution in Muster, limited to five fixed names in Muster files. The alternative, providers written as code, breaks "no execution from config".
2. **Environment values and strict charts.** An environment's `values` go to every chart in it. A chart with a strict `values.schema.json` rejects keys meant for other charts, so keep them under `global:`.
3. **Helm calls reference repo files.** The values come from Muster, but the chart folder and any secrets file are paths, so `deploy` runs helm from the repository root, and a pipeline needs a checkout of the same revision. `helm package` output or an OCI chart reference would remove that, later.
4. **Comparing environments.** The layout makes `diff stacks/customer-platform/qa.yaml stacks/customer-platform/prod.yaml` meaningful on its own. A `muster compare --stack customer-platform qa prod` showing the merged values per app side by side is not on the roadmap yet. Given how much comparing matters, it may be worth moving into the MVP; it would reuse `values --explain`, whose output already diffs well.
5. **Repetition across stacks.** With values in three places, a value that is the same for one app in every environment of a stack, or for one app in one environment of every stack, is repeated in each stack's environment file. That is the price of one obvious place per value; bring back a shared layer only if the repetition becomes a real maintenance problem.
6. **No type files.** `types/<type>.yaml` was dropped to see whether it is needed. A type's contract is inferred from what its consumers map (section 4). Bring type files back if consumers disagree on output names in practice, or if a type needs optional outputs.
