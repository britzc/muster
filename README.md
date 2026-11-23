# Muster

Muster is a CLI from Creedworks that keeps continuous delivery for many applications, stacks and environments easy to manage. You define apps once and bind them per environment. Muster works out which releases each stack has, in what order and against which cluster, and generates the Helm values for each one, from minikube to production.

**Muster prints, and acts only when told to.** Every command prints what Muster knows or generates. `muster deploy`, `uninstall`, `restart` and `rollback` print the `helm` or `kubectl` calls they would make, and run them only with `--yes`, so the rules for running them live in Muster instead of in every pipeline. Muster talks to no cluster itself (helm and kubectl do, through the kube context each environment names), reads no environment variables, and writes no file except a stack's image versions file, and that only with `--write`.

**Day to day: [GUIDE.md](GUIDE.md)**, one page of tasks and the commands for them. **Pipelines: [CI.md](CI.md)**, `muster ci gitlab` and the example's GitLab pipeline. **Every command and flag: [CLI.md](CLI.md)**, generated from the binaries. **What changed: [CHANGELOG.md](CHANGELOG.md).**

Background: [CONCEPT.md](CONCEPT.md) (the why, and [how environments, stacks and apps map onto clusters, namespaces and releases](CONCEPT.md#how-they-map-onto-kubernetes-and-aws)) and [SCHEMA.md](SCHEMA.md) (the file format and rules).

## Install

Download the binaries for your platform from the [releases](https://github.com/britzc/muster/releases) (`muster-<os>-<arch>`, and `muster-ci-<os>-<arch>` to generate pipelines; checksums in `SHA256SUMS`) and put them on your `PATH`, for example on Linux:

```bash
for b in muster muster-ci; do
  curl -fsSLo $b https://github.com/britzc/muster/releases/latest/download/$b-linux-amd64
  chmod +x $b && sudo mv $b /usr/local/bin/
done
```

Two binaries:

- **`muster`** reads the repository, composes the values and makes every `helm` and `kubectl` call. Deploying needs `helm` on the `PATH`; the kube context in each environment file decides which cluster a call reaches.
- **`muster-ci`** generates the pipelines a CI system runs Muster in, run as `muster ci gitlab` (`muster ci` runs `muster-ci` beside `muster` or on the `PATH`, and other CI systems can follow as `muster ci <system>`). It knows the repository only through `muster`: `muster list … --json`, `versions`, and the calls `deploy`, `uninstall`, `restart` and `rollback --json` give. So it makes no call of its own, and every rule Muster applies holds in a pipeline too. Leave it out where no pipeline is generated.

`muster help` and `muster <command> --help` describe every command and flag; `muster ci help` the pipelines'.

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
ENVIRONMENT  TIER         CONTEXT   DISABLED  REASON
dev          development  minikube  no        -
qa           testing      minikube  no        -
prod         production   minikube  no        -

$ muster releases --env dev --stack hello
STACK  ORDER  APP      RELEASE        MODE  CHART           NAMESPACE  CONTEXT   PROTECTED  SECRETS                            DISABLED  REASON
hello  1      mongodb  hello-mongodb  helm  charts/mongodb  hello-dev  minikube  no         -                                  yes       mongodb is disabled in dev: Not used yet; web gets a database in 1.2.0 (HELLO-12)
hello  2      web      hello-web      helm  charts/web      hello-dev  minikube  no         stacks/hello/dev.web.secrets.yaml  no        -
hello  3      nginx    hello-nginx    helm  charts/nginx    hello-dev  minikube  no         -                                  no        -
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
# muster: then -f secrets://stacks/hello/qa.web.secrets.yaml
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
helm upgrade --install hello-web charts/web --kube-context minikube --namespace hello-qa --wait --timeout 3m --create-namespace -f - -f secrets://stacks/hello/qa.web.secrets.yaml
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

**Ship and promote a version.** A version starts in dev and moves on by promotion: qa takes only what dev runs, and prod only what qa runs (`from` in [`muster.yaml`](examples/hello/muster.yaml)). dev already runs web 1.1.0, which qa can't be given directly:

```console
$ muster versions set web=1.1.0 --env qa --stack hello
muster: V008: qa takes web's versions only from dev (its from in muster.yaml); promote them: muster versions promote --env qa --stack hello; or, to set one here anyway, such as a rollback, add --confirm qa

$ muster versions promote --env qa --stack hello --write     # what dev runs, into qa
muster: warning D001: mongodb is disabled in qa: Not used yet; web gets a database in 1.2.0 (HELLO-12); its version is kept
muster: wrote stacks/hello/qa.versions.yaml
$ muster deploy --env qa --stack hello --yes

$ muster versions promote --env prod --stack hello --write   # what qa runs, into prod
$ muster deploy --env prod --stack hello --yes
```

Each environment also says which tags it takes, and prod takes release tags only. Had a feature build reached qa, promoting it would stop there:

```console
muster: error V004: stacks/hello/prod.versions.yaml: versions.web.app: tag "feature-x" is not accepted in prod; its tags match [0-9]+\.[0-9]+\.[0-9]+(-alpine)? (versions.tags in environments/prod.yaml)
```

**Tear down.** prod is in the production tier, so it also needs `--confirm prod`:

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

`--mode helm,mock` leaves out external members, which have nothing to deploy. An app deploy with `--all-stacks` covers every stack in the environment that has the app, since an environment can host several. Rows come in deploy order, each environment after the one it promotes from, so a loop deploys dev, then qa, then prod:

```sh
for env in $(muster list environments --stack hello --names); do
  muster deploy --env "$env" --stack hello --yes
done
```

A stack deploys in an environment only after it deployed in the environment before; within one environment, deploy one stack at a time (a stack's members already go in order). Stacks don't wait for each other. [`muster ci gitlab`](CI.md) turns a matrix into a GitLab child pipeline, a stage per tier and a job per cell, each deploy job waiting for the same cell in the environment before. [MATRIX.md](MATRIX.md) explains the continuous delivery principles behind matrix deployments.

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

## Branch environments

An environment in an `ephemeral` tier has an **instance** per branch: one environment, deployed as many times as there are branches, each instance in a namespace of its own and torn down whole when the branch goes. Many branches can have instances at once. [examples/cache](examples/cache) has one, `temp`.

**1. It is an ordinary environment, deployed once per branch.** Its files are the ones any environment has, under its own name; every instance shares them:

```yaml
# muster.yaml
tiers:
  - name: development
    environments: { dev: {} }
  - name: review
    ephemeral: true                       # an instance per branch
    environments: { temp: {} }

# environments/temp.yaml
namespace: "{stack}-{env}-{instance}"     # a namespace per stack and instance
helm:
  createNamespace: true
```

`stacks/<stack>/temp.yaml` says how each stack runs in it (here Postgres and Redis in the instance's namespace, where prod has RDS and ElastiCache), and `temp.externals.yaml` and `temp.<app>.secrets.yaml` work as anywhere else. Nothing is provisioned up front: an instance comes into being with its first deploy and goes with its teardown.

**2. Its versions come from its versions file, and a deploy can override them.**

```console
$ muster versions set api=1.0 api.migrator=4.29.2 --env temp --stack shop --write   # stacks/shop/temp.versions.yaml, committed like any other
```

That file holds what every instance runs. Muster ties it to no other environment: keeping it current, say with what dev runs, is up to your pipelines, which know what your environments are called and what they mean. A deploy overrides any of it for that one run with `--version <app>[.<image>]=<tag>` (repeatable), which is never written: a branch passes its own build, and keeps the rest. Every image of every app that runs its own chart must get a version from one or the other, or the deploy fails: an instance never runs a tag from a values file or a chart's default. A member filled by a provider's chart (Postgres, Redis) or external takes none: its chart's values pin its image, like any configuration.

**3. Deploy and tear down an instance** by naming it with `--instance` (`-i`), such as the branch's slug or `mr-<iid>`:

```console
$ muster deploy --env temp --stack shop --instance mr-7 --version api=abc-123
muster: printing only; add --yes to run
helm upgrade --install shop-db charts/postgres --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --create-namespace -f -
helm upgrade --install shop-cache charts/redis --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --create-namespace -f -
helm upgrade --install shop-api charts/api --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --create-namespace -f -
$ muster uninstall --env temp --stack shop --instance mr-7
muster: printing only; add --yes to run
helm uninstall shop-api --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --ignore-not-found
helm uninstall shop-cache --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --ignore-not-found
helm uninstall shop-db --kube-context minikube --namespace shop-temp-mr-7 --wait --timeout 3m --ignore-not-found
kubectl delete namespace shop-temp-mr-7 --context minikube --ignore-not-found --wait --timeout 3m
```

The api in `mr-7` reaches the Postgres and the Redis in `mr-7`. Uninstalling a whole stack removes every release, protected ones too, then the namespace with everything in it; running it again is fine. Uninstalling one app (`--app`) is an ordinary uninstall, and keeps the namespace.

**How versions change, everywhere:**

| | An environment that stays (dev, qa, prod) | An ephemeral environment (temp) |
|---|---|---|
| Its versions file | `versions set`, `promote` | `versions set` only |
| A new build, in a pipeline | `ci gitlab --app api --tag 1.2.0 --commit …`: written to dev's file, committed, then promoted along the chain | `ci gitlab --instance mr-7 --version api=abc-123`: given to that deploy only, never written |
| `--version` on a deploy | refused | overrides the versions file for that run |

**The rules,** which `muster validate` and every command check:

- An ephemeral tier is never production, and its environments have no `from` and are no environment's `from` (E001). Their namespace uses `{stack}`, `{env}` and `{instance}`, so a teardown deletes one stack of one instance, and sets `helm.createNamespace: true`; they are not `gitops` (E002).
- An ephemeral environment's versions change only by `versions set`, and a deploy's `--version` (E003).
- `--instance` is lowercase letters, digits and `-`, makes a namespace of at most 63 characters, is required in an ephemeral environment by `releases`, `values`, `deploy`, `uninstall`, `restart` and `rollback`, and refused elsewhere (E004).

**In GitLab:** `muster ci gitlab --instance <name>` gives a branch's pipeline: a deploy job per stack, and a stop job that GitLab runs when the branch is deleted ([CI.md](CI.md#a-branchs-instance)).

## Pipelines

`muster ci` generates the pipelines a CI system runs Muster in: [CI.md](CI.md) has `muster ci gitlab`, the pipelines it makes, and [the hello example's GitLab pipeline](CI.md#the-example-pipeline).

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

An environment hosts a stack when the stack lists it under `environments` in its `stack.yaml` (`stacks/<stack>/<env>.yaml` is optional, for what differs there), and runs every member of it in one of three [modes](CONCEPT.md#members-and-their-modes): `helm` (the default), `mock` or `external`. Every requirement is met by a member of the same stack; something outside Muster, such as a shared database, is added as an external member.

## Commands

Each command's every flag, as `--help` prints it, is in [CLI.md](CLI.md).

| Command | What it does |
|---|---|
| `muster validate` | Prints every problem in the repository, with its rule code; exits 1 if there are errors, so it works as a CI gate |
| `muster list environments\|stacks\|apps` | Prints each, and whether it is disabled and why; `--names` for the ones not disabled, one per line, for scripts; `--json`. For environments also the tier and kube context; `--env <env> --get context` prints the context alone |
| `muster list tiers` | Prints the tiers in deploy order, a pipeline stage each; `--json` gives each one's `production` and `ephemeral` |
| `muster releases [--app <app>] <selection>` | Prints the releases in deploy order, with everything needed to act on them; `--json` for scripts |
| `muster values --app <app> <selection>` | Prints the values one release gets: the file to pass to `helm -f` |
| `muster values [--app <app>] <selection> --explain` | The same values over the chart's defaults, with a header per release, for review |
| `muster deploy [--app <app>] <selection>` | Prints the `helm upgrade --install` calls, in deploy order; `--yes` runs them `--json` gives them as data instead (each call's `argv`, or the `skip` reason, and a deploy's `values`), as `uninstall`, `restart` and `rollback` do, for a tool that writes the calls into a job; it runs nothing |
| `muster uninstall [--app <app>] <selection>` | Prints the `helm uninstall` calls, in reverse order; `--yes` runs them, `--confirm <env>` too for a production environment. A whole stack in an instance of an [ephemeral environment](#branch-environments) also loses its namespace |
| `muster restart [--app <app>] <selection>` | Prints a `kubectl rollout restart` per release, in order, each followed by a `rollout status` that waits; `--yes` runs them |
| `muster rollback [--app <app>] <selection>` | Prints the `helm rollback` calls, in reverse order, to each release's previous revision or `--to <revision>`; `--yes` runs them |
| `muster versions [--app <app>] <selection>` | Prints each release's images, the version each gets and where it comes from; `--json` for scripts |
| `muster versions set\|promote … --write` | Changes a stack's image versions in one environment (the only file Muster writes); `set --confirm <env>` sets one past the chain, such as a rollback |
| `muster ci gitlab [--stack <stack> \| --app <app>]` | Runs `muster-ci`, which prints a GitLab child pipeline for a matrix: a stage per tier, a job per cell ([CI.md](CI.md#gitlab-child-pipelines)); its jobs only print their calls unless `--yes` is given. It reads the repository through `muster`, so a name the repository doesn't have, or a version Muster would refuse, fails generating, not a job |

Every command that selects releases takes the same form, `muster <command> --env <env> --stack <stack> [--app <app>]`, and only flags, in any order: Muster reads no environment variables, so a command line always means the same thing. The stack is always named, even when an environment hosts only one, so a command means the same thing after a stack is added. Each selection flag has a short form for typing: `-e`, `-s`, `-a`, `-i` for `--instance`, and `-t` for `ci gitlab --tag`.

| Selection | Selects |
|---|---|
| `--env <env> --stack <stack>` | Every member of the stack in the environment (repeat `--stack` for more) |
| `--app <app> --env <env> --stack <stack>` | Just that app in that stack |
| `--env <env> --all-stacks` | Every stack the environment hosts |
| `--app <app> --env <env> --all-stacks` | That app in every hosted stack that contains it |
| `--instance <name>` with any of these | The instance of an [ephemeral environment](#branch-environments); required there, refused elsewhere |
| `--version <app>[.<image>]=<tag>` with `deploy`, `values` or `releases` | Overrides the versions file of an [ephemeral environment](#branch-environments) for that run only, and is never written (repeatable); refused elsewhere |

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

`--names` prints only the ones not disabled, one per line: the form for scripts and pipelines. `--json` gives an array of `name`, `disabled` and `reason`. For environments, the table also gives each one's tier and kube context, and `--json` its `tier`, `from`, `production`, `ephemeral`, `gitops` and `context`.

`--get <field>` prints one of those for the environment `--env` names, alone on a line: `context`, `tier`, `from`, `production`, `ephemeral` or `gitops`. It is for a pipeline step that needs the value before Muster runs, such as a cloud CLI writing the kubeconfig, or `kubectl`. It fails when the environment has no value for the field, so a script never runs `kubectl --context ""` against whatever context is active:

```bash
ctx=$(muster list environments --env prod --get context)   # prod-eks
aws eks update-kubeconfig --name prod --alias "$ctx"
```

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
muster list environments --ephemeral=false         # those without an instance per branch (--ephemeral: those with)
muster list environments --env prod --get context   # prod's kube context, alone on a line
```

| Command | Takes |
|---|---|
| `list environments` | `--env <env>`, `--app <app>`, `--stack <stack>`, `--mode <mode>`, `--versioned`, `--production[=false]`, `--ephemeral[=false]`, `--get <field>` (with `--env`) |
| `list stacks` | `--app <app>`, `--env <env>`, `--mode <mode>`, `--versioned` |
| `list apps` | `--env <env>`, `--stack <stack>`, `--mode <mode>`, `--versioned` |

Each also takes `--names` or `--json`. The filters combine, and each narrows to where an environment hosts a stack that has the app. `--stack` repeats; `--mode` (helm, mock or external, the mode `releases` shows) repeats or takes a comma-separated list. A name that doesn't exist is an error, not an empty list. `list` reads only the stack files, so a stack with errors elsewhere in the repository never stops it (`validate` reports those). Environments come in deploy order: each after the environment it promotes from (`from` in `muster.yaml`), and otherwise tier by tier, each by name. Apps of one stack come in member order; otherwise names are sorted. A name is disabled only when it is disabled everywhere the filters select: a stack with one disabled member is not.

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
- A protected release never gets an `uninstall`, and there is no flag to change that. Remove a database by hand. The one exception is the teardown of an instance of an [ephemeral environment](#branch-environments), which deletes its namespace and everything in it.
- An uninstall that would change an environment in a `production: true` tier also needs `--confirm <env>`.
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

A rollback changes the cluster only. The repository still records the newer version and values, so the next deploy brings them back. It's the quick fix, for a person at a terminal; a generated pipeline has no job for it. To keep it, roll the version back in the repository ([Rolling back](#rolling-back)):

```bash
muster versions set web=1.0.0 --env dev --stack hello --write   # then promote it through qa to prod
```

**Check one release** with helm directly; `muster releases --app <app> … --json` gives the release, namespace and kube context:

```bash
helm status hello-web --namespace hello-qa --kube-context minikube
helm history hello-web --namespace hello-qa --kube-context minikube
```

### `versions`

Image versions live in `stacks/<stack>/<env>.versions.yaml`, apart from the values ([why](CONCEPT.md#8-image-versions)). `muster versions` changes the file; nobody edits it by hand:

```bash
muster versions set web=1.2.0 nginx=1.27.4-alpine --env dev --stack hello --write  # ship to dev
muster versions promote --env qa --stack hello --write                             # what dev runs, into qa
muster versions promote --env prod --stack hello --write                           # what qa runs, into prod
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
- **Versions move along the chain.** An environment with a [`from`](SCHEMA.md#3-root-musteryaml) takes them only by `promote` from that environment, which `--from` defaults to; `set` there is refused (V008), and so is `promote --from` any other environment. So a version reaches prod only after it ran in qa, and qa only after dev. `set` works where the chain starts, and for an app the environment before doesn't run as its own chart (a mock in qa, say), which `validate` warns about (P004).
- **Each environment says which tags it takes** ([`versions.tags`](SCHEMA.md#9-environment-environmentsenvyaml), e.g. release tags only in prod). `set` and `promote` refuse a tag the environment doesn't take, and `validate`, `values` and `deploy` refuse one from anywhere, so a feature build can go to qa but never to prod, whichever pipeline or laptop tries.
- **Commit the file once its deploy passed.** Every later deploy uses it until it changes, so without a commit the next pipeline deploys the old version. Committing only after the deploy passed means a version in an environment's file has passed there, so the next environment promotes only what passed. Muster never commits; the [ship and promote jobs](CI.md#the-example-pipeline) do it in CI.
- **Without `--write`**, `set` and `promote` print the new file, to review first.

#### Rolling back

A rollback is a version change like any other, recorded in the versions file and then deployed, so every later deploy keeps it:

```bash
muster versions set web=1.0.0 --env prod --stack hello --confirm prod --write
muster deploy --app web --env prod --stack hello --yes
# then commit stacks/hello/prod.versions.yaml
```

- **`--confirm <env>` lets `set` skip the chain.** An environment with a `from` otherwise takes versions only by promote (V008); naming it with `--confirm` is the deliberate exception, and the commit records it. The tag is still checked against the environment's `versions.tags`.
- **A later promote copies what the environment before runs.** If qa still runs the bad version, the next promote into prod brings it back, so roll qa back too, or ship a fix through the chain. prod's jobs are manual by default, so a person starts that promote.
- **Pipelines and other systems** do the same through [`ci gitlab --yes --action rollback`](CI.md#the-example-pipeline): one job in the environment, which sets the version, deploys, and commits once the deploy passed.

`muster rollback`, helm's previous revision, is the faster fix in the cluster only: the next deploy brings back what the file records ([below](#deploy-uninstall-restart-and-rollback)).

The file's rules (fallback to values, which apps take versions, what is checked) are in [SCHEMA.md §10](SCHEMA.md#stacksstackenvversionsyaml).

### Database migrations

A migration, such as Liquibase or Flyway, runs inside the app's own chart as a Helm `pre-install,pre-upgrade` hook Job: Helm runs it before it changes the app's pods, and waits for it. Muster runs no scripts itself, so this is where the step belongs, and it gets what everything else in the chart gets: [examples/cache](examples/cache)'s api has [`charts/api/templates/migrate.yaml`](examples/cache/charts/api/templates/migrate.yaml), which applies [`migrations/changelog.yaml`](examples/cache/charts/api/migrations/changelog.yaml) with Liquibase.

- **The database it migrates is wired.** The api requires `sql`, and the Job takes the host, user and secret from the same values as the app, so it migrates the Postgres chart in dev and qa, RDS in prod, and each branch's own database in its instance of temp.
- **Its image is versioned with the app.** `images: { app: image.tag, migrator: migrations.image.tag }` in `app.yaml` puts the Liquibase image in the versions files, so `versions set api.migrator=…` changes it and `promote` moves it.
- **A failed migration stops the deploy.** The hook fails, so `helm upgrade` fails and `muster deploy --yes` stops there: the app's pods are not changed, and a generated pipeline commits nothing and goes no further.
- **The database deploys first**, since the stack lists it before the api and each release waits for the one before.
- **A rollback doesn't undo a migration.** `muster rollback` rolls back the release, not the schema: keep each change one the previous version of the app can run with (expand, then contract), or roll the schema back with the tool's own command.

A hook, rather than a member of its own: Muster passes `--wait`, which waits for Deployments but not for a plain Job to finish, and Helm can't upgrade a Job in place.

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
$ muster versions set web=1.1.0 web.chart=1.4.0 --env dev --stack hello --write
$ muster deploy --app web --env dev --stack hello
helm upgrade --install hello-web oci://123456789012.dkr.ecr.eu-west-1.amazonaws.com/charts/web --version 1.4.0 --kube-context … -f -
$ muster versions promote --env qa --stack hello --write   # the image and the chart
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
| [examples/basic](examples/basic) | The smallest useful repository, and the one to copy: two apps (backend and frontend) in one stack, `shop`, in dev and qa (qa promoting from dev), with each app's values, each environment's values and image versions. No providers, mocks, external members, wiring or secrets: add those only when a stack needs them ([GUIDE.md](GUIDE.md#start-small)) |
| [examples/hello](examples/hello) | A hello world web app with nginx in front of it and a disabled mongodb, one stack in dev, qa and prod, every app's version captured per environment, an API key per environment in SOPS, and a [GitLab pipeline](CI.md#the-example-pipeline) for matrix deployments |
| [examples/cache](examples/cache) | One stack whose database and cache are Postgres and Redis in the cluster in dev, qa and each branch's instance, and RDS and ElastiCache in prod: slot apps (`chart: none`), a provider for each, `external` members in prod with their endpoints in `prod.externals.yaml`, the api wired to whichever fills them, its [Liquibase migrations](#database-migrations), and `temp`, an [ephemeral environment](#branch-environments) |

