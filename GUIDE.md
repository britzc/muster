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

## Start small

[examples/basic](examples/basic) is all most repositories need: apps with their charts and values, a stack, its environments, and image versions. Add the rest only when a stack needs it:

| When | Add | See |
|---|---|---|
| An app needs another's address or a database's connection | `requires` and `provides`, which wire themselves | [CONCEPT.md §4](CONCEPT.md#4-dependencies-members-providers-externals-and-mocks) |
| A database is Postgres in one environment and MSSQL in another | a provider | [SCHEMA.md §6](SCHEMA.md#6-providers-providersproviderprovideryaml) |
| Part of the stack runs outside the cluster (RDS, EC2) | an `external` member | [CONCEPT.md §4](CONCEPT.md#4-dependencies-members-providers-externals-and-mocks) |
| A test environment fakes an integration | a `mock` member | [CONCEPT.md](CONCEPT.md#members-and-their-modes) |
| A secret per environment | a SOPS file | [README](README.md#secrets-sops) |
| A chart is published, not in the repository | `chart: oci://…` | [README](README.md#charts-in-a-registry) |

## Tasks

| To… | Run |
|---|---|
| Check the repository (CI does on every merge request) | `muster validate` |
| See what there is | `muster list environments`, `muster list apps --stack hello` |
| See what a stack deploys where | `muster releases --env qa --stack hello` |
| See the values a release gets, and where each came from | `muster values --app web --env qa --stack hello` (`--explain` adds the chart's defaults) |
| Compare two environments | `diff stacks/hello/qa.yaml stacks/hello/prod.yaml`, or diff two `muster values` |
| See which versions run where | `muster versions --env prod --stack hello` |
| Ship a version to an environment | `muster versions set web=1.2.0 --env qa --stack hello --write`, commit, `muster deploy --app web --env qa --stack hello --yes` |
| Ship an init container's or a sidecar's version | `muster versions set web.sidecar=1.37.0 --env qa --stack hello --write` (`web=…` alone sets web's image named `app`) |
| Pin an image by digest | `muster versions set web=1.2.0@sha256:… …` |
| Promote what qa runs to prod | `muster versions promote --from qa --env prod --stack hello --write`, commit, `muster deploy --env prod --stack hello --yes` |
| Deploy a stack, or one app | `muster deploy --env qa --stack hello --yes`, `muster deploy --app web --env qa --stack hello --yes` |
| Restart | `muster restart --app web --env qa --stack hello --yes` |
| Roll back fast | `muster rollback --app web --env prod --stack hello --yes` (the cluster only: the next deploy brings the repository's version back) |
| Roll back for good | `muster versions set web=<previous> --env prod --stack hello --write` (the previous version is in `git log -p stacks/hello/prod.versions.yaml`), or `git revert` the commit that changed it (a promote commit covers every production environment); commit, then `muster deploy --env prod --stack hello --yes` |
| Freeze an environment, a stack or an app | `disabled: true` and a `reason` in its file, committed ([README](README.md#disabling-an-environment-a-stack-or-an-app)) |
| Tear down | `muster uninstall --env qa --stack hello --yes` (`--confirm prod` for production; databases are never removed) |

Without `--yes`, `deploy`, `uninstall`, `restart` and `rollback` print the `helm` or `kubectl` calls they would make: run them that way first.

## Adding things

| To add… | Create | Then |
|---|---|---|
| An app | `charts/<app>/` (or `chart: oci://…`), `apps/<app>/app.yaml`, `apps/<app>/values.yaml` | List it in a stack's `stack.yaml` |
| A stack | `stacks/<stack>/stack.yaml` with its members in deploy order | Host it in an environment |
| An environment | `environments/<env>.yaml`: kube context, namespace, values | `stacks/<stack>/<env>.yaml` for each stack it hosts, and `muster versions set … --write` for its versions |

`muster validate` says what is missing. The GitLab pipeline picks up new environments, stacks and apps by itself ([README](README.md#gitlab-ci)).

## When a command fails

Exit code 2: the command line is wrong (a flag, or a name the repository doesn't have); the message says what exists. Exit code 1: the repository refuses or has a problem (a rule code such as `V004` or `D001`, listed in [SCHEMA.md §12](SCHEMA.md#12-validation)), or helm or kubectl failed.
