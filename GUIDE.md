# Muster day to day

One page for working with a Muster repository. The commands use [examples/hello](examples/hello): an app `web` with `nginx` in front, in one stack `hello`, in `dev`, `qa` and `prod`. Every command prints; the ones that change a cluster run only with `--yes`. The details are in the [README](README.md).

## Three ideas

```
environment  →  one cluster (an AWS account and region) and its shared settings
  stack      →  usually one namespace; apps deployed together, in order
    app      →  one Helm release
```

| You change… | In |
|---|---|
| An app's values everywhere | `apps/<app>/values.yaml` |
| Everything about a stack in one environment: replicas, hosts, resources | `stacks/<stack>/<env>.yaml` |
| What every release in an environment gets: ingress class, storage, pull policy | `environments/<env>.yaml` |
| Which version an environment runs | `stacks/<stack>/<env>.versions.yaml`, only with `muster versions` |
| The tiers, the order of environments, and where each takes versions from | `tiers` in `muster.yaml` |
| Where a stack runs | `environments` in `stacks/<stack>/stack.yaml` |

## Start small

[examples/basic](examples/basic) is all most repositories need: apps with their charts and values, a stack, its environments in order (qa promotes from dev), and image versions. Add the rest only when a stack needs it:

| When | Add | See |
|---|---|---|
| An app needs another's address or a database's connection | `requires` and `provides`, which wire themselves | [CONCEPT.md §4](CONCEPT.md#4-dependencies-members-providers-externals-and-mocks) |
| A database is Postgres in one environment and MSSQL in another | a provider | [SCHEMA.md §6](SCHEMA.md#6-providers-providersproviderprovideryaml), [examples/cache](examples/cache) (Redis, ElastiCache in prod) |
| Part of the stack runs outside the cluster (RDS, ElastiCache, EC2) | an `external` member | [CONCEPT.md §4](CONCEPT.md#4-dependencies-members-providers-externals-and-mocks), [examples/cache](examples/cache) |
| A test environment fakes an integration | a `mock` member | [CONCEPT.md](CONCEPT.md#members-and-their-modes) |
| A secret per environment | a SOPS file | [README](README.md#secrets-sops) |
| A chart is published, not in the repository | `chart: oci://…` | [README](README.md#charts-in-a-registry) |
| A database migration (Liquibase, Flyway) with each deploy | a `pre-install,pre-upgrade` hook Job in the app's chart, its image under `images` | [README](README.md#database-migrations), [examples/cache](examples/cache) |
| A deployment per branch, torn down when the branch goes | an `ephemeral` tier, and `--instance` | [README](README.md#branch-environments), [examples/cache](examples/cache) |

## Tasks

| To… | Run |
|---|---|
| Check the repository (CI does on every merge request) | `muster validate` |
| See what there is | `muster list environments`, `muster list apps --stack hello` |
| See what a stack deploys where | `muster releases --env qa --stack hello` |
| See the values a release gets, and where each came from | `muster values --app web --env qa --stack hello` (`--explain` adds the chart's defaults) |
| Compare two environments | `diff stacks/hello/qa.yaml stacks/hello/prod.yaml`, or diff two `muster values` |
| See which versions run where | `muster versions --env prod --stack hello` |
| Ship a version | `muster versions set web=1.2.0 --env dev --stack hello --write`, `muster deploy --app web --env dev --stack hello --yes`, and commit once it passes. Only the first environment of the chain takes `set` |
| Ship an init container's or a sidecar's version | `muster versions set web.sidecar=1.37.0 --env dev --stack hello --write` (`web=…` alone sets web's image named `app`) |
| Pin an image by digest | `muster versions set web=1.2.0@sha256:… …` |
| Promote to the next environment | `muster versions promote --env qa --stack hello --write` (from dev, qa's `from` in `muster.yaml`), `muster deploy --env qa --stack hello --yes`, and commit once it passes; then the same for prod, from qa |
| Ship through CI | `muster generate gitlab-ci --app web --tag 1.2.0 --auto --commit ci/versions.sh` writes the pipeline: dev, then qa, then prod, each committing once it passed. `--to dev` stops in dev; a later `--action promote` takes it on |
| Put environments in order | `prod: { from: qa }` under its tier in `muster.yaml`: prod deploys after qa and takes versions only from it. `manual`, on the tier or the environment, says whether a person starts its jobs (default: the tier's `production`) |
| Deploy a stack, or one app | `muster deploy --env qa --stack hello --yes`, `muster deploy --app web --env qa --stack hello --yes` |
| Restart | `muster restart --app web --env qa --stack hello --yes` |
| Roll back | `muster versions rollback web=1.0.0 --current 1.1.0 --env prod --stack hello --confirm prod --write`, deploy, commit; or a pipeline with `ACTION=rollback`. prod then rejects 1.1.0, so no promote brings it back; `--accept` takes it back ([README](README.md#rolling-back)) |
| Roll back fast, in the cluster only | `muster rollback --app web --env prod --stack hello --yes`: helm's previous revision, until the next deploy brings the repository's version back |
| Freeze an environment, a stack or an app | `disabled: true` and a `reason` in its file, committed ([README](README.md#disabling-an-environment-a-stack-or-an-app)) |
| Tear down | `muster uninstall --env qa --stack hello --yes` (`--confirm prod` for production; databases are never removed, except with a branch's instance) |
| Deploy a branch, and tear it down | `muster deploy --env preview --stack shop --instance pr-142 --yes`, then `muster uninstall --env preview --stack shop --instance pr-142 --yes`, which also deletes its namespace ([README](README.md#branch-environments)); in CI, `muster generate gitlab-ci --instance pr-142 --auto` |

Without `--yes`, `deploy`, `uninstall`, `restart` and `rollback` print the `helm` or `kubectl` calls they would make: run them that way first.

## Adding things

| To add… | Create | Then |
|---|---|---|
| An app | `charts/<app>/` (or `chart: oci://…`), `apps/<app>/app.yaml`, `apps/<app>/values.yaml` | List it in a stack's `stack.yaml` |
| A stack | `stacks/<stack>/stack.yaml` with its members in deploy order, and the environments it runs in | `stacks/<stack>/<env>.yaml` where something differs |
| An environment | `environments/<env>.yaml`: kube context, namespace, values | its name under `environments` in each stack it hosts (and `stacks/<stack>/<env>.yaml` where something differs), an entry under a tier in `muster.yaml` for its kind and where it sits in the chain, and its versions by `muster versions promote` (or `set`, if it is first) |
| An environment per branch | an environment as above, in a tier with `ephemeral: true`, with `{stack}` and `{instance}` in its namespace and `helm.createNamespace: true`, and no `from` or versions file | `muster validate` |

`muster validate` says what is missing. The GitLab pipeline picks up new environments, stacks and apps by itself ([README](README.md#gitlab-ci)); an ephemeral environment only in a pipeline generated with `--instance` ([README](README.md#branch-environments)).

## When a command fails

Exit code 2: the command line is wrong (a flag, or a name the repository doesn't have); the message says what exists. Exit code 1: the repository refuses or has a problem (a rule code such as `V004` or `D001`, listed in [SCHEMA.md §12](SCHEMA.md#12-validation)), or helm or kubectl failed.
