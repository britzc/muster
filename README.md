# Muster

Muster is a CLI from Creedworks that keeps continuous delivery for many applications, stacks and environments easy to manage. You define apps once and bind them per environment. Muster works out which releases each stack has, in what order and against which cluster, and generates the Helm values for each one, from minikube to production.

**Muster prints, and acts only when told to.** Every command prints what Muster knows or generates. `muster deploy`, `uninstall`, `restart` and `rollback` print the `helm` or `kubectl` calls they would make, and run them only with `--yes`, so the rules for running them live in Muster instead of in every pipeline. Muster talks to no cluster itself (helm and kubectl do, through the kube context each environment names), reads no environment variables, and writes no file except a stack's image versions file, and that only with `--write`.

**Day to day: [GUIDE.md](GUIDE.md)**, one page of tasks and the commands for them.

Background: [CONCEPT.md](CONCEPT.md) (the why, and [how environments, stacks and apps map onto clusters, namespaces and releases](CONCEPT.md#how-they-map-onto-kubernetes-and-aws)) and [SCHEMA.md](SCHEMA.md) (the file format and rules).

## Install

Download the binary for your platform from the [releases](https://github.com/britzc/muster/releases) (`muster-<os>-<arch>`, checksums in `SHA256SUMS`) and put it on your `PATH`, for example on Linux:

```bash
curl -fsSLo muster https://github.com/britzc/muster/releases/latest/download/muster-linux-amd64
chmod +x muster && sudo mv muster /usr/local/bin/
```

One binary. Deploying needs `helm` on the `PATH`; the kube context in each environment file decides which cluster a call reaches. `muster help` and `muster <command> --help` describe every command and flag.

## Getting started: the hello example

[examples/hello](examples/hello) is a hello world web application, `web`, with `nginx` in front of it, deployed as one stack, `hello`, to `dev`, `qa` and `prod`. The stack also has a small `mongodb`, disabled everywhere until web uses it. Every output below was captured from it.

```
src/web/                        the hello world app (Node), built into an image
charts/web/, charts/nginx/      the two Helm charts
apps/web/app.yaml               its images (web, an init container, a sidecar), and the url it provides
apps/nginx/app.yaml             its image, and the upstream it requires: web's url
apps/mongodb/app.yaml           its image
stacks/hello/stack.yaml         members, in deploy order: mongodb, web, then nginx
stacks/hello/<env>.yaml         each app's values in dev, qa and prod; mongodb disabled
stacks/hello/<env>.versions.yaml   the image versions of every app in each environment
stacks/hello/<env>.web.secrets.yaml   web's API key in each environment, SOPS-encrypted
.sops.yaml, sops-demo.agekey    which key encrypts them, and that key (a demo key: never commit a real one)
environments/<env>.yaml         kube context, namespace, values for every release there
.gitlab-ci.yml                  its pipeline: matrix deployments (see GitLab CI)
```

**Check the repository and see what a stack contains:**

```console
$ cd examples/hello
$ muster validate
ok: 3 environments, 1 stacks, 3 apps

$ muster list environments
ENVIRONMENT  DISABLED  REASON
dev          no        -
qa           no        -
prod         no        -

$ muster releases --env dev --stack hello
STACK  ORDER  APP      RELEASE        MODE  CHART           NAMESPACE  CONTEXT   PROTECTED  SECRETS  DISABLED  REASON
hello  1      mongodb  hello-mongodb  helm  charts/mongodb  hello-dev  minikube  no         -        yes       mongodb is disabled in dev: Not used yet; web gets a database in 1.2.0 (HELLO-12)
hello  2      web      hello-web      helm  charts/web      hello-dev  minikube  no         -        no        -
hello  3      nginx    hello-nginx    helm  charts/nginx    hello-dev  minikube  no         -        no        -
```

**Every image's version is captured per environment**, in `stacks/hello/<env>.versions.yaml`, mongodb's too. web's pod also runs an init container and a sidecar, each with its own version:

```console
$ muster versions --env dev --stack hello
STACK  APP      IMAGE    VALUE          FROM                            DISABLED  REASON
hello  mongodb  app      7.0.14         stacks/hello/dev.versions.yaml  yes       mongodb is disabled in dev: Not used yet; web gets a database in 1.2.0 (HELLO-12)
hello  web      app      1.1.0          stacks/hello/dev.versions.yaml  no        -
hello  web      init     1.37.0         stacks/hello/dev.versions.yaml  no        -
hello  web      sidecar  1.37.0         stacks/hello/dev.versions.yaml  no        -
hello  nginx    app      1.27.4-alpine  stacks/hello/dev.versions.yaml  no        -
```

**See the values each release gets.** Later layers win (app → environment → stack in environment → wiring → versions), and every key names the file that set it. nginx gets web's url through wiring, so nothing names it by hand:

```console
$ muster values --app web --env qa --stack hello
# muster: values for hello-web [helm] charts/web
message: hello world from qa # stacks/hello/qa.yaml › values.web
global: # environments/qa.yaml › values
  environment: qa # environments/qa.yaml › values
  imagePullPolicy: IfNotPresent # environments/qa.yaml › values
image: # stacks/hello/qa.versions.yaml › versions.web.app
  tag: 1.0.0 # stacks/hello/qa.versions.yaml › versions.web.app
init: # stacks/hello/qa.versions.yaml › versions.web.init
  image:
    tag: 1.36.1 # stacks/hello/qa.versions.yaml › versions.web.init
sidecar: # stacks/hello/qa.versions.yaml › versions.web.sidecar
  image:
    tag: 1.36.1 # stacks/hello/qa.versions.yaml › versions.web.sidecar

$ muster values --app nginx --env qa --stack hello
# muster: values for hello-nginx [helm] charts/nginx
global: # environments/qa.yaml › values
  environment: qa # environments/qa.yaml › values
  imagePullPolicy: IfNotPresent # environments/qa.yaml › values
upstream: # wiring: upstream ← member web (helm)
  url: http://hello-web.hello-qa.svc:8080 # wiring: upstream ← member web (helm)
image: # stacks/hello/qa.versions.yaml › versions.nginx.app
  tag: 1.27.3-alpine # stacks/hello/qa.versions.yaml › versions.nginx.app
```

**Compare two environments**, or add `--explain` to see the chart's defaults too:

```console
$ diff <(muster values --app web --env qa --stack hello) <(muster values --app web --env prod --stack hello)
2,7c2,8
< message: hello world from qa # stacks/hello/qa.yaml › values.web
…
> message: hello world from prod # stacks/hello/prod.yaml › values.web
…
> replicaCount: 2 # stacks/hello/prod.yaml › values.web
```

**See the helm calls a deploy or teardown would make**, in order (uninstall runs in reverse). Without `--yes`, nothing runs. The disabled mongodb keeps its place with the reason:

```console
$ muster deploy --env qa --stack hello
muster: printing only; add --yes to run
# skip hello-mongodb: mongodb is disabled in qa: Not used yet; web gets a database in 1.2.0 (HELLO-12)
helm upgrade --install hello-web charts/web --kube-context minikube --namespace hello-qa --wait --timeout 3m --create-namespace -f -
helm upgrade --install hello-nginx charts/nginx --kube-context minikube --namespace hello-qa --wait --timeout 3m --create-namespace -f -
```

**Deploy every environment.** All three point at the `minikube` context, in separate namespaces; build the web images into minikube first. web's API key comes from a [SOPS](#secrets-sops) file, so deploying needs `sops`, the helm-secrets plugin and the example's demo key. With `--yes`, Muster runs each call, passing the release's values to helm on stdin and the secrets file as `-f secrets://…`:

```console
$ minikube start
$ minikube image build -t web:1.0.0 src/web
$ minikube image build -t web:1.1.0 src/web
$ export SOPS_AGE_KEY_FILE=$PWD/sops-demo.agekey
$ for env in $(muster list environments --names); do muster deploy --env $env --stack hello --yes; done

$ kubectl port-forward -n hello-qa svc/hello-nginx 8080:80 &
$ curl -i localhost:8080
HTTP/1.1 200 OK
X-Served-By: nginx/1.27.3
…
{"message":"hello world from qa","environment":"qa","version":"1.0.0","apiKey":"…AKEY"}
```

web shows the last four characters of its key only, so you can see that qa got qa's.

**Ship and promote a version.** Each environment says which tags it takes; prod takes release tags only:

```console
$ muster versions set web=1.1.0 nginx=1.27.4-alpine --env qa --stack hello --write
muster: wrote stacks/hello/qa.versions.yaml
$ muster deploy --env qa --stack hello --yes

$ muster versions set web=feature-x --env prod --stack hello
muster: error V004: stacks/hello/prod.versions.yaml: versions.web.app: tag "feature-x" is not accepted in prod; its tags match [0-9]+\.[0-9]+\.[0-9]+(-alpine)? (versions.tags in environments/prod.yaml)

$ muster versions promote --from qa --env prod --stack hello --write
muster: wrote stacks/hello/prod.versions.yaml
$ muster deploy --env prod --stack hello --yes
```

**Tear down.** prod is a production environment, so it also needs `--confirm prod`:

```console
$ muster uninstall --env qa --stack hello --yes
$ muster uninstall --env prod --stack hello --yes --confirm prod
```

For real clusters, set `cluster.context` in each `environments/<env>.yaml` to its kube context.

## Matrix deployments

A matrix deployment covers several environments, stacks and apps at once. Its cells are Muster's cells: one app of one stack in one environment that hosts the stack. `muster list … --names` gives each axis from the repository, without what is [disabled](#disabling-an-environment-a-stack-or-an-app), so the matrix is never written by hand and never drifts from it (the table leaves out `--names`):

| Matrix | Rows × columns | Each cell |
|---|---|---|
| Every stack everywhere | `list environments` × `list stacks --env <env>` | `muster deploy --env <env> --stack <stack>` |
| One stack everywhere | `list environments --stack <stack>` | `muster deploy --env <env> --stack <stack>` |
| One app everywhere | `list environments --app <app> --mode helm,mock` | `muster deploy --app <app> --env <env> --all-stacks` |
| Every app in one environment | `list apps --env <env> --mode helm,mock` | `muster deploy --app <app> --env <env> --all-stacks` |
| Every app everywhere | `list environments` × `list apps --env <env> --mode helm,mock` | `muster deploy --app <app> --env <env> --all-stacks` |

`--mode helm,mock` leaves out external members, which have nothing to deploy. An app deploy with `--all-stacks` covers every stack in the environment that has the app, since an environment can host several. Rows come in deploy order, so a loop deploys test environments before production:

```sh
for env in $(muster list environments --stack hello --names); do
  muster deploy --env "$env" --stack hello --yes
done
```

Cells in different environments are independent and can run at the same time; within one environment, deploy one stack at a time (a stack's members already go in order). `muster generate gitlab-ci` turns a matrix into a GitLab child pipeline with a job per cell, which the [GitLab pipeline](#gitlab-ci) runs:

```console
$ muster generate gitlab-ci --auto                 # every stack everywhere; production jobs manual
stages: [dev, qa, prod]
deploy hello in dev:
  stage: dev
  environment: dev
  resource_group: dev
  when: on_success
  script:
    - muster deploy --env dev --stack hello --yes
…
$ muster generate gitlab-ci --by app --app web --tag 1.2.0 --production=false  # a test build of web, where it runs
$ muster generate gitlab-ci --action restart --skip local                      # restart every stack, but on a laptop
```

`--by stack` (the default) gives a job per stack an environment hosts, `--by app` one per app it deploys, and an app named one stage with a job per environment. What is disabled gets no job, an app only gets one where it runs a chart or a mock, and an uninstall from production carries `--confirm`. `muster generate gitlab-ci --help` has every flag. [MATRIX.md](MATRIX.md) explains the continuous delivery principles behind matrix deployments.

## Disabling an environment, a stack or an app

`disabled: true`, with a `reason`, turns something off for changes: a code freeze in prod, a release candidate under test, or an app locked in qa for extended testing. It is optional and defaults to `false`, and it goes in the file that owns what it turns off:

```yaml
# environments/prod.yaml: the whole environment
disabled: true
reason: Code freeze until 2027-01-05 (CHG-1234)

# stacks/hello/qa.yaml: the stack in qa
disabled: true
reason: Release candidate under test

# stacks/hello/qa.yaml: one app of the stack in qa
members:
  web:
    disabled: true
    reason: Extended testing of 1.1.0, until 2026-11-14 (QA-88)
```

- **Nothing changes it.** `deploy`, `uninstall`, `restart`, `rollback`, `versions set` and `promote` refuse what the command names when it is disabled (D001), with the reason: the environment, a stack named with `--stack`, or an app named in one. A wider command skips it instead, with a `# skip` line, the way it skips external and protected members: a stack deploy deploys the rest of the stack, `--all-stacks` the other stacks, and promoting every app keeps a disabled one's version.
- **Pipelines never see it.** `muster list … --names` leaves out what is disabled, so a pipeline built from it offers no job for it.
- **Everything still reads it.** `list`, `releases` and `versions` show a DISABLED and a REASON column (and `disabled` and `reason` in `--json`), `values` still prints its values, and `validate` still checks it, so nothing breaks unnoticed while it's off. Apps that need it still get its outputs: a disabled app keeps running at the version it has.
- **A reason is required**, and only with `disabled: true` (S001). Lifting it is removing those lines, in a commit, so Git records who did and when. There is no flag to override it.

In the hello example, `mongodb` is disabled in every environment: it is part of the stack and its version is recorded, but nothing deploys it until web uses it.

## GitLab CI

[examples/hello/.gitlab-ci.yml](examples/hello/.gitlab-ci.yml) is the hello repository's pipeline. It names no environment, stack or app: every one comes from [`muster list --names`](#list), so adding an environment or a stack to the repository adds it to the pipeline, and disabling one takes it out. It deploys [matrices](#matrix-deployments): its `plan` job turns the run's inputs into flags for [`muster generate gitlab-ci`](#matrix-deployments), and runs the child pipeline it prints, a stage per environment and a job per cell.

- **Image:** build it from this repository's [Dockerfile](Dockerfile) (`docker build -t registry.example.com/platform/muster:1 .`). It holds `muster`, `helm` with the helm-secrets plugin (checked against its author's signature), `sops` (checked against its release checksums), `kubectl` and `git`.
- **Secrets:** the age key that decrypts the SOPS files, as a GitLab CI/CD variable `SOPS_AGE_KEY_FILE` of type File. It takes precedence over the example's `SOPS_AGE_KEY_FILE`, which points at the demo key.
- **Charts in a registry:** helm needs to be logged in to the registry before a deploy. That is the pipeline's job, done however your platform logs in to it; Muster only names the chart, and depends on nothing but helm. See [Charts in a registry](#charts-in-a-registry).
- **Cluster access:** the job's kubeconfig, from the GitLab agent for Kubernetes (set `cluster.context` to the agent's context, e.g. `platform/agents:qa`) or a `KUBECONFIG` file variable. Muster only names the context.
- **Writing versions back:** a project access token with `write_repository`, in the masked variable `DEPLOY_TOKEN`. `ship` and `promote` start from the latest main, take in anything merged while they run before pushing, and take turns (`resource_group: versions`), so they never push over each other.
- **Environments CI can't reach:** list them in the variable `SKIP_ENVIRONMENTS`, e.g. a `local` environment on a laptop.

| Job | When | What it does |
|---|---|---|
| `check` | every merge request and main | `muster validate`, then every stack's deploy in every environment, printed only |
| `plan`, `matrix` | main | Deploys every stack: the non-production environments right away, production as manual jobs |
| `plan`, `matrix` | Run pipeline | Deploys or uninstalls what the inputs choose, as manual jobs (below) |
| `ship` | triggered by an app's pipeline with `APP`, and `TAG` (optionally with `DIGEST`), `CHART` (the version of its chart in a registry) or both | `muster versions set` in every non-production stack where the app takes versions (`list --versioned`), commit and push (`[skip ci]`), deploy the app there |
| `promote` | main, manual | Copies into each production environment, stack by stack, the versions of the last non-production environment before it; commits, pushes and deploys. A tag production doesn't take stops it |

**Only main deploys to every environment.** A pipeline run by hand from another branch offers only the non-production environments (`muster list environments --production=false`), for testing a branch. Protect the production environments in GitLab to enforce it there too; with required approvals, their jobs wait for an approver.

**Run pipeline** asks for an `action` (deploy, uninstall, restart or rollback), whether to act on a `stack` or an `app`, and for an app optionally its name and a `version`:

| Choice | Child pipeline |
|---|---|
| `stack` | A stage per environment, a job per stack it hosts: `muster <action> --env <env> --stack <stack> --yes` |
| `app`, no name | A stage per environment, a job per app it deploys: `muster <action> --app <app> --env <env> --all-stacks --yes` |
| `app` with a name | One stage, a job per environment that deploys the app |
| `app` with a name and a `version` (deploy only) | The same, each job first running `muster versions set <app>=<version> … --write` (the app's image named `app` when it has several) where the app runs its own chart. The change stays in the job and is not committed: for testing a build |

An app only gets a job where it is a chart or a mock (`--mode helm,mock`), so no job does nothing. Start one job, several, or a whole stage with Run all manual. Jobs for different environments run at the same time; a `resource_group` per environment queues two jobs in the same one. Uninstalling from a production environment adds `--confirm <env>`: starting the job is the confirmation. Without a `version`, a job deploys the versions the repository records.

## Repository layout

Muster reads a repository with a fixed layout. The folders are the catalogue, so there is no registry to keep in sync. Each folder answers one question, and everything in it is either a Helm chart, a plain Helm values file, or a small Muster file saying how they fit together. Every file and its fields are in [SCHEMA.md](SCHEMA.md) (§2 lists them all).

### Where values go

Three places, and one rule: **anything that isn't the app's own default goes in the stack's environment file.**

| Values for… | File | Usually owned by |
|---|---|---|
| The app, everywhere | `apps/<app>/values.yaml` | the app team |
| Every release in one environment (ingress class, storage class, pull policy) | `environments/<env>.yaml` → `values:` | the platform team |
| One member in one stack in one environment (replicas, hosts, resources, log level), whatever chart it runs: its own, a mock's or a provider's | `stacks/<stack>/<env>.yaml` → `values.<app>` | the stack owner |

Later wins, so the stack's environment file has the last word: app → environment → stack in environment, then wiring outputs and image versions ([the full layer order](SCHEMA.md#layer-order)). Comparing qa with prod for a stack is `diff stacks/<stack>/qa.yaml stacks/<stack>/prod.yaml`. Image tags are not values: they live in `stacks/<stack>/<env>.versions.yaml` ([`muster versions`](#versions)) and beat any tag in the values.

| Folder | The question it answers | What Helm gets from it |
|---|---|---|
| `charts/` | Which Helm charts exist? | The chart for every release: your apps' charts, mock charts, and charts that fill a slot (e.g. `postgresql`). Used unmodified, exactly as `helm` would; vendor dependencies with `helm dependency build`. A chart can also stay in a registry ([below](#charts-in-a-registry)) |
| `apps/<app>/` | What is this app? | `values.yaml`: the app's values everywhere, the file the app team already has. `app.yaml` is not passed to Helm: it says what the app needs (a database) and provides, and which chart value holds its image tag |
| `stacks/<stack>/` | Which apps make up this system, and how is it set up in each environment? | `stack.yaml` lists the members in deploy order, which is the order of the `helm` calls. `<env>.yaml` makes the environment host the stack, sets each member's mode (real chart, mock or external) and holds each app's values there. Beside it: the image versions, the outputs of members Helm doesn't deploy, and SOPS values for helm-secrets |
| `environments/` | Where does a deploy go? | The `--kube-context`, `--namespace` and Helm settings (`--wait`, `--timeout`, `--create-namespace`) of every call, and `values:` every release there gets. The context picks the cluster, region and account. `gitops: true` hands the releases to a GitOps controller: Muster then builds no helm or kubectl calls |

Database slots that one environment fills with Postgres and another with MSSQL use providers: `providers/<provider>/provider.yaml` names the type it delivers, an optional chart and its outputs ([SCHEMA.md](SCHEMA.md) §6). Muster has none built in.

An environment hosts a stack when `stacks/<stack>/<env>.yaml` exists, and runs every member of it in one of three [modes](CONCEPT.md#members-and-their-modes): `helm` (the default), `mock` or `external`. Every requirement is met by a member of the same stack; something outside Muster, such as a shared database, is added as an external member.

## Commands

| Command | What it does |
|---|---|
| `muster validate` | Prints every problem in the repository, with its rule code; exits 1 if there are errors, so it works as a CI gate |
| `muster list environments\|stacks\|apps` | Prints each, and whether it is disabled and why; `--names` for the ones not disabled, one per line, for scripts; `--json` |
| `muster releases [--app <app>] <selection>` | Prints the releases in deploy order, with everything needed to act on them; `--json` for scripts |
| `muster values --app <app> <selection>` | Prints the values one release gets: the file to pass to `helm -f` |
| `muster values [--app <app>] <selection> --explain` | The same values over the chart's defaults, with a header per release, for review |
| `muster deploy [--app <app>] <selection>` | Prints the `helm upgrade --install` calls, in deploy order; `--yes` runs them |
| `muster uninstall [--app <app>] <selection>` | Prints the `helm uninstall` calls, in reverse order; `--yes` runs them, `--confirm <env>` too for a production environment |
| `muster restart [--app <app>] <selection>` | Prints a `kubectl rollout restart` per release, in order, each followed by a `rollout status` that waits; `--yes` runs them |
| `muster rollback [--app <app>] <selection>` | Prints the `helm rollback` calls, in reverse order, to each release's previous revision or `--to <revision>`; `--yes` runs them |
| `muster versions [--app <app>] <selection>` | Prints each release's images, the version each gets and where it comes from; `--json` for scripts |
| `muster versions set\|promote … --write` | Changes a stack's image versions in one environment (the only file Muster writes) |
| `muster generate gitlab-ci [--app <app>]` | Prints a GitLab child pipeline for a matrix: a stage per environment, a job per cell ([Matrix deployments](#matrix-deployments)) |

Every command that selects releases takes the same form, `muster <command> --env <env> --stack <stack> [--app <app>]`, and only flags, in any order: Muster reads no environment variables, so a command line always means the same thing. The stack is always named, even when an environment hosts only one, so a command means the same thing after a stack is added. Each selection flag has a short form for typing: `-e`, `-s`, `-a`, and `-t` for `generate gitlab-ci --tag`.

| Selection | Selects |
|---|---|
| `--env <env> --stack <stack>` | Every member of the stack in the environment (repeat `--stack` for more) |
| `--app <app> --env <env> --stack <stack>` | Just that app in that stack |
| `--env <env> --all-stacks` | Every stack the environment hosts |
| `--app <app> --env <env> --all-stacks` | That app in every hosted stack that contains it |

**Exit codes:** 0 when the command did what it says. 2 when the command line is wrong: an unknown command or flag, a missing, conflicting or malformed flag or argument, or a name the repository doesn't have where the command line uses it (an environment, stack or app that doesn't exist, a stack the environment doesn't host, an app not in the stack); fix the command. 1 when the command line is fine but the result isn't: the repository has a problem or refuses the change (validation errors, something disabled, a tag the environment doesn't take, nothing to do), or helm or kubectl failed; fix the repository or the cluster.

`--repo <dir>` points at the repository, or any folder inside it (default: the current folder). [Getting started](#getting-started-the-hello-example) shows most commands' output; the notes below cover what it doesn't.

### `list`

What there is to select, and whether each is [disabled](#disabling-an-environment-a-stack-or-an-app):

```console
$ muster list apps --stack hello
APP      DISABLED  REASON
mongodb  yes       mongodb is disabled in dev: Not used yet; web gets a database in 1.2.0 (HELLO-12)
web      no        -
nginx    no        -

$ muster list apps --env qa --names
nginx
web
```

`--names` prints only the ones not disabled, one per line: the form for scripts and pipelines. `--json` gives an array of `name`, `disabled` and `reason`.

```
muster list environments                           # every environment, in deploy order
muster list stacks                                 # every stack
muster list apps                                   # every app

muster list environments --app web                 # the environments where a stack has web
muster list environments --stack hello             # the environments that host hello
muster list stacks --env qa                        # the stacks qa hosts
muster list stacks --app web --env qa              # the stacks in qa that have web
muster list apps --env qa                          # the apps in the stacks qa hosts
muster list apps --stack hello                     # its members, in deploy order

muster list apps --env qa --mode helm,mock         # what deploying qa installs (no external members)
muster list environments --app web --mode helm     # where web runs a chart
muster list stacks --app web --env qa --versioned  # where versions set web=… works in qa
muster list environments --production=false        # the test environments: dev qa (--production: prod)
```

| Command | Takes |
|---|---|
| `list environments` | `--app <app>`, `--stack <stack>`, `--mode <mode>`, `--versioned`, `--production[=false]` |
| `list stacks` | `--app <app>`, `--env <env>`, `--mode <mode>`, `--versioned` |
| `list apps` | `--env <env>`, `--stack <stack>`, `--mode <mode>`, `--versioned` |

Each also takes `--names` or `--json`. The filters combine, and each narrows to where an environment hosts a stack that has the app. `--stack` repeats; `--mode` (helm, mock or external, the mode `releases` shows) repeats or takes a comma-separated list. A name that doesn't exist is an error, not an empty list. `list` reads only the stack files, so a stack with errors elsewhere in the repository never stops it (`validate` reports those). Environments come in deploy order: those with `production: false` first, then the production ones, each by name. Apps of one stack come in member order; otherwise names are sorted. A name is disabled only when it is disabled everywhere the filters select: a stack with one disabled member is not.

`--mode helm` includes apps whose chart comes from a provider (a database, say). `--versioned` narrows to where the app takes image versions: it runs its own chart and names images in `app.yaml`, so `versions set` can change it there.

### `releases`

`--json` gives one object per member, external and disabled members included (`disabled` and `reason`). External members carry `outputs` and `outputsFrom` in place of a chart; `protected` is what the app's `app.yaml` says. `releases` is data only: it never contains a command, so saving or sharing it can't change an environment.

### `values`

Muster merges the layers with Helm's own rules and leaves the chart's defaults to Helm ([SCHEMA.md §11](SCHEMA.md#11-resolution)). Tests check that Helm ends up with exactly the values it would get from the layers as separate files: for every example release, and for random layers in a fuzz test.

A mock or a provider's chart doesn't get the app's values file or its image versions: it gets the environment's values, then `values.<app>` from the stack's environment file. `values` refuses an `external` member, since Muster deploys nothing for it.

Muster doesn't render manifests: `muster values --app <app> … | helm template <release> <chart> -f -` does, exactly as a deploy would, and `| kubectl apply --dry-run=server -f -` lets the cluster check them.

### `deploy`, `uninstall`, `restart` and `rollback`

For a stack with external and protected members (a database, say), the skipped ones keep their place with the reason:

```console
$ muster uninstall --env prod --stack customer-platform
muster: printing only; add --yes to run
helm uninstall customer-platform-billing --kube-context prod-eks --namespace customer-platform --wait --timeout 15m --ignore-not-found
helm uninstall customer-platform-payments --kube-context prod-eks --namespace customer-platform --wait --timeout 15m --ignore-not-found
# skip customer-platform-ledger-service: external: runs outside Muster's reach
# skip customer-platform-sanctions-gateway: external: runs outside Muster's reach
# skip customer-platform-orders-db: protected: Muster never builds an uninstall for it; remove it by hand if you mean to
```

The rules are applied once, in Muster:

- Without `--yes`, nothing runs. With it, the calls run one after the other, from the repository root (chart paths are relative to it), and the first failure stops the rest.
- `deploy` and `restart` run in member order, `uninstall` and `rollback` in reverse, across the stacks too.
- External members, and every release in a `gitops: true` environment (owned by the GitOps controller), get no call: only a `# skip` line with the reason. So do [disabled](#disabling-an-environment-a-stack-or-an-app) ones, for every command.
- A protected release never gets an `uninstall`, and there is no flag to change that. Remove a database by hand.
- An uninstall that would change a `production: true` environment also needs `--confirm <env>`.
- `uninstall` passes `--ignore-not-found`, so a teardown that stopped half way can simply be run again.
- Every call names `--kube-context` and `--namespace`, so the same calls work on minikube, EKS or any other cluster.
- `deploy` passes the release's values on stdin (`-f -`), followed by any `secrets://` files for helm-secrets.

**Restart** a release's deployments, statefulsets and daemonsets, found by Helm's standard `app.kubernetes.io/instance` label. In an environment with `helm.wait`, each restart is followed by a `kubectl rollout status` that waits up to `helm.timeout`:

```console
$ muster restart --app web --env qa --stack hello
muster: printing only; add --yes to run
kubectl rollout restart deployment,statefulset,daemonset -l app.kubernetes.io/instance=hello-web --context minikube --namespace hello-qa
kubectl rollout status deployment,statefulset,daemonset -l app.kubernetes.io/instance=hello-web --context minikube --namespace hello-qa --timeout 3m
```

A workload without the label isn't restarted: kubectl reports "No resources found" and succeeds, so check that your charts set it.

**Roll back** a release to its previous revision, or to the one `--to` names (`helm history <release>` lists them; `--to` takes a single release):

```console
$ muster rollback --app web --env prod --stack hello --to 3
muster: printing only; add --yes to run
helm rollback hello-web 3 --kube-context minikube --namespace hello-prod --wait --timeout 3m
```

A rollback changes the cluster only. The repository still records the newer version and values, so the next deploy brings them back. It's the quick fix; to keep it, set the version it went back to and commit, as for any other version ([`versions`](#versions)):

```bash
muster versions set web=1.0.0 --env prod --stack hello --write
```

**Check one release** with helm directly; `muster releases --app <app> … --json` gives the release, namespace and kube context:

```bash
helm status hello-web --namespace hello-qa --kube-context minikube
helm history hello-web --namespace hello-qa --kube-context minikube
```

### `versions`

Image versions live in `stacks/<stack>/<env>.versions.yaml`, apart from the values ([why](CONCEPT.md#8-image-versions)). `muster versions` changes the file; nobody edits it by hand:

```bash
muster versions set web=1.1.0 nginx=1.27.4-alpine --env qa --stack hello --write  # ship to qa
muster versions promote --from qa --env prod --stack hello --write                # what qa runs, into prod
```

```console
$ muster versions --env prod --stack hello
STACK  APP      IMAGE    VALUE          FROM                             DISABLED  REASON
hello  mongodb  app      7.0.14         stacks/hello/prod.versions.yaml  yes       mongodb is disabled in prod: Not used yet; web gets a database in 1.2.0 (HELLO-12)
hello  web      app      1.0.0          stacks/hello/prod.versions.yaml  no        -
hello  web      init     1.36.1         stacks/hello/prod.versions.yaml  no        -
hello  web      sidecar  1.36.1         stacks/hello/prod.versions.yaml  no        -
hello  nginx    app      1.27.3-alpine  stacks/hello/prod.versions.yaml  no        -
```

- **An app's images** are named in `app.yaml` with the value path each tag goes in: `images: { app: image.tag }`, or one per container the chart runs. hello's web names an init container and a sidecar beside its own image:
  ```yaml
  images:
    app: image.tag
    init: init.image.tag
    sidecar: sidecar.image.tag
  ```
  Each is versioned, promoted and tag-checked on its own: `set web.sidecar=1.37.0`. `set web=1.2.0` sets the image named `app` (the only image, when there is one). An app that names none takes no versions. The chart must take each tag at a map path (`sidecar.image.tag`), not inside a list (`initContainers[0].image`).
- **A version is a tag**, such as `1.4.2`, optionally with a digest that is passed on unchecked: `1.4.2@sha256:…`.
- **Each environment says which tags it takes** ([`versions.tags`](SCHEMA.md#9-environment-environmentsenvyaml), e.g. release tags only in prod). `set` and `promote` refuse a tag the environment doesn't take, and `validate`, `values` and `deploy` refuse one from anywhere, so a feature build can go to qa but never to prod, whichever pipeline or laptop tries.
- **Commit the file.** Every later deploy uses it until it changes, so without a commit the next pipeline deploys the old version. Muster never commits; the [`ship` and `promote` jobs](#gitlab-ci) do it in CI.
- **Without `--write`**, `set` and `promote` print the new file, to review first.

The file's rules (fallback to values, which apps take versions, what is checked) are in [SCHEMA.md §10](SCHEMA.md#stacksstackenvversionsyaml).

### Charts in a registry

An app's chart, a provider's or a mock's can stay in an OCI registry such as ECR, or in a classic chart repository, instead of in `charts/` ([SCHEMA.md §1](SCHEMA.md#1-general-rules)):

```yaml
# apps/web/app.yaml
chart: oci://123456789012.dkr.ecr.eu-west-1.amazonaws.com/charts/web

# providers/postgres/provider.yaml
chart: https://charts.example.com/stable/postgresql    # the repository's URL, then the chart
chartVersion: 15.5.0
```

An app's own chart moves through the environments like its image: its version is in each versions file, as `web.chart`:

```console
$ muster versions set web=1.1.0 web.chart=1.4.0 --env qa --stack hello --write
$ muster deploy --app web --env qa --stack hello
helm upgrade --install hello-web oci://123456789012.dkr.ecr.eu-west-1.amazonaws.com/charts/web --version 1.4.0 --kube-context … -f -
$ muster versions promote --from qa --env prod --stack hello --write   # the image and the chart
```

- **Exact versions only** (`1.4.0`, `1.5.0-rc.1`), no ranges, so the same files always deploy the same chart. `versions.tags` checks image tags, not chart versions.
- **Muster never fetches a chart; helm does,** with the login helm already has (`helm registry login` for an OCI registry, `helm repo add` for a classic repository that needs credentials; nothing for a public one). Logging helm in is up to the pipeline or the person running Muster, and credentials never go in the reference.
- **Muster can't see the chart's defaults.** `values --explain` says so, with the `helm show values …` command that shows them. So an image of such an app takes its tag from the versions file or the values, never the chart's default (V007): the tag policy still sees every tag.
- **Images** come from any registry already: Muster only sets the tag. Put the repository in the values (`image.repository: 123456789012.dkr.ecr.eu-west-1.amazonaws.com/web`, or per environment), and give the cluster pull access (on EKS, the nodes' IAM role).

`muster values --app web … | helm template hello-web oci://… --version 1.4.0 -f -` renders it as a deploy would.

### Secrets (SOPS)

Muster never decrypts secrets: `deploy` passes a release's SOPS file after its values as `-f secrets://…`, for the [helm-secrets](https://github.com/jkroepke/helm-secrets) plugin to decrypt with `sops`, and `validate` catches a plaintext one before it's committed ([SCHEMA.md §10](SCHEMA.md#stacksstackenvappsecretsyaml)).

In the hello example, each environment has its own API key for web:

```console
$ cat .sops.yaml
creation_rules:
  - path_regex: stacks/.*\.secrets\.yaml$
    age: age1z86mtheqdjh93ny95r86yh3ndve6guhddf0pvtcwf9s5epp6j5gqzpsswq      # sops-demo.agekey: demo only

$ muster deploy --app web --env prod --stack hello
helm upgrade --install hello-web charts/web … -f - -f secrets://stacks/hello/prod.web.secrets.yaml

$ sops edit stacks/hello/prod.web.secrets.yaml            # change a secret (needs the key)
```

The chart turns `apiKey` into a Kubernetes Secret; the value never appears in Muster's output. To render with secrets yourself: `muster values --app web … | helm template … -f - -f secrets://stacks/hello/prod.web.secrets.yaml`, which then holds them in plain text.

**Setting it up:** install `sops` and the helm-secrets plugin. With Helm 4 that is two signed plugins, `secrets` and `secrets-getter` (`helm plugin install https://github.com/jkroepke/helm-secrets/releases/download/v4.7.9/secrets-getter-4.7.9.tgz`, and the same for `secrets`), verified against the author's key ([the Dockerfile](Dockerfile) shows how). Point `SOPS_AGE_KEY_FILE` at the age key. The example commits a demo key so it deploys out of the box; a real repository commits only `.sops.yaml` with its public recipient, and keeps the private key in CI (a File variable) and with the people allowed to change secrets.

## Examples

| Folder | Shows |
|---|---|
| [examples/basic](examples/basic) | The smallest useful repository, and the one to copy: two apps (backend and frontend) in one stack, `shop`, in dev and qa, with each app's values, each environment's values and image versions. No providers, mocks, external members, wiring or secrets: add those only when a stack needs them ([GUIDE.md](GUIDE.md#start-small)) |
| [examples/hello](examples/hello) | A hello world web app with nginx in front of it and a disabled mongodb, one stack in dev, qa and prod, every app's version captured per environment, an API key per environment in SOPS, and a [GitLab pipeline](#gitlab-ci) for matrix deployments |

