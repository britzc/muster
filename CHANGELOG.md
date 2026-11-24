# Changelog

What changed in each release of Muster, newest first. What Muster does today is in [README.md](README.md), [CI.md](CI.md) and [CLI.md](CLI.md).

## v0.17.0 (2026-11-24)

**Added**

- **A release train in the hello example.** A pipeline schedule on `main`, on the hour, with the inputs `action: promote` and `env: prod` and the variable `APPROVE_ENVIRONMENT=prod`, promotes prod from qa by itself, and changes prod only when something new passed qa. Only a schedule's pipeline honours `APPROVE_ENVIRONMENT`. See [A release train](CI.md#a-release-train).
- `muster ci gitlab --env <env>`: only that environment, such as the one a release train promotes into (`--to` is a chain up to one).
- `muster ci gitlab --approve <env>` with `--auto`: that manual environment's jobs start themselves too, in this pipeline only; naming it is the approval, as a schedule gives it. Every other pipeline still waits for a person there.

## v0.16.0 (2026-11-24)

**Added**

- **Release trains: a promote deploys only what it changed.** Every `--action promote` job runs `muster versions promote … --write --exit-unchanged` first; with nothing new to promote, the job ends there, passing, with no helm call (no new Helm revision, no hooks) and nothing committed. So a pipeline schedule can promote an environment on the hour, and it changes only when something new passed the environment before. See [A release train](CI.md#a-release-train).
- `muster versions promote --exit-unchanged`: exit 3 when the environment already holds the versions it would promote. `versions set` and `promote` no longer rewrite a file whose content would not change.

## v0.15.0 (2026-11-24)

**Breaking**

- **A pipeline's jobs follow where apps are defined in stacks.** `muster ci gitlab` has a job per stack (`--by stack`, the default) or per app in each stack (`--by app`): every job is one stack's, so none deploys outside it, and an app in several stacks has a job in each, moving on in each by itself. `--by app` used to give one job per app across every stack that has it (`--all-stacks`); it now gives what `--by cell` did, and `--by cell` is gone (it says to use `--by app`). `--stack` and `--app` can be given together. Jobs per app are named `<stack>/<app>` (`deploy hello/web in qa`), and their commits name the stack (`ship web=1.2.0 to dev (hello)`). The hello pipeline's `deploy` input offers `stack` or `app`.
- **Install `muster` and `muster-ci` v0.15.0 together.** The JSON contract between them is 2: each call in `deploy`, `uninstall`, `restart` and `rollback --json` names its `stack` and `app`. `muster-ci` refuses a `muster` of contract 1, and the other way round, with a message that says to install both from one release.

**Changed**

- Generating a pipeline makes a few `muster` calls per environment, not one per job: each environment's calls and members come in one `--json` call, and each job takes its own. The pipelines are the same as before; a large matrix generates in a fraction of the time.

## v0.14.0 (2026-11-24)

The same as v0.13.1: it carries v0.13's changes (above all `muster ci gitlab` and the second binary, `muster-ci`) under a new minor version. Upgrading from v0.12 or earlier, read v0.13.0's breaking changes.

## v0.13.1 (2026-11-24)

**Fixed**

- Release notes link to the files they name at the release's tag: a relative link such as `CI.md` led to a page that doesn't exist on the release page.

## v0.13.0 (2026-11-24)

**Breaking**

- **Pipelines are `muster ci gitlab`.** Pipeline generation moved out of `muster` into a second binary, `muster-ci`, which `muster ci` runs (beside `muster`, or on the `PATH`). `muster generate gitlab-ci` is gone, and says to use `muster ci gitlab`, which takes the same flags. Install both binaries, from one release; the CI image carries both. See [CI.md](CI.md).
- **A rollback is `versions set --confirm <env>`.** `versions rollback`, `rejected:` in versions files, and `--current` and `--accept` are gone. `muster versions set <app>=<older> --env <env> --stack <stack> --confirm <env> --write` takes a version back in one environment, past the chain; `muster ci gitlab --action rollback` gives the same as a job. A later promote copies what the environment before runs, so roll that one back too, or ship a fix through the chain. Delete any `rejected:` block from your versions files.
- **No bases for branch environments.** `bases:` in `muster.yaml` and `base:` on an environment are gone (and E005 with them). An ephemeral environment has its own files like any other, `environments/<env>.yaml` and `stacks/<stack>/<env>.yaml`, and each branch is an instance of it with `--instance`. Rename a base's files to the environment's name.
- **Stricter checks of where releases land**, so `muster validate` may now fail on a repository that passed before:
  - a release is unique per kube context, namespace and name across every environment (X006), so two environments on one cluster can no longer share a namespace and reach each other's releases: give them their own;
  - an ephemeral environment's namespace needs `{env}` as well as `{stack}` and `{instance}`;
  - a namespace, with its placeholders filled in, must be a valid Kubernetes namespace of at most 63 characters (S002).
- **An invalid tag in a pipeline is Muster's own error.** `muster ci gitlab --tag` and `--chart` are checked by `muster versions set`, so a bad one fails generating with V003 or V006 (exit 1) instead of a separate check (exit 2).

**Added**

- `muster version [--json]`: the release, and the contract of the JSON `muster-ci` reads. `muster-ci` refuses a `muster` whose contract is not its own; `muster ci version` shows both.
- `deploy`, `uninstall`, `restart` and `rollback --json`: the calls as data, each one's `argv` (or the reason it gets none) and a deploy's `values`, for a tool that writes them into a job. It runs nothing, so it refuses `--yes`.
- `muster list tiers [--json]`: the tiers in deploy order, a pipeline stage each. `list environments` gives `manual` too, in `--json` and `--get`.
- A values file that exists but can't be read is an error (S001), instead of a layer left out.
- Each release has `muster-ci-<os>-<arch>` beside `muster-<os>-<arch>`, both reporting the release as their version, all in `SHA256SUMS`.

**Docs**

- [CI.md](CI.md): `muster ci gitlab`, its pipelines, a branch's instance in GitLab, and the example's GitLab pipeline, apart from Muster itself.
- [CLI.md](CLI.md): every command and flag, as `--help` prints them, generated from the binaries.
- This changelog, from v0.1.0.

## v0.12.0 (2026-11-17)

- Branch environments take their versions from their own versions file, which only `versions set` changes; `deploy`, `values` and `releases` take `--version <app>[.<image>]=<tag>` to override one for that run, never written. An instance never runs a tag from a values file or a chart's default: a deploy missing a version fails. `generate gitlab-ci --instance --version` passes the overrides to its jobs.
- Branch environments could be built from a base (removed again since).

## v0.11.0 (2026-11-10)

- **Breaking:** a generated pipeline acts only with `--yes` written out; without it, its jobs print their calls, as every command does. `--yes false` is refused as a typo.
- Flags come from the command line only: never from environment variables or a config file, so `--yes`, `--write` and `--confirm` are always what was typed.
- Rollback jobs wait for a person only in manual environments.

## v0.10.0 (2026-11-10)

- `versions rollback`, recording the version it replaced as rejected (replaced since by `versions set --confirm`).
- `versions set` and `promote` say when they only print.
- A namespace belongs to one repository; a namespace shared with something else is a risk Muster can't see, and the docs say so.
- The hello pipeline gets each environment's kube context with `list environments --get context`, for a login step.

## v0.9.0 (2026-11-10)

- `list environments` gives each environment's tier and kube context; `--env <env> --get <field>` prints one value alone, for a pipeline step that needs it before Muster runs.

## v0.8.0 (2026-11-03)

- Pipeline generation knows no CI system: a pipeline is built once and written for GitLab by a writer of its own, so another CI system is another writer. Output unchanged.

## v0.7.0 (2026-11-02)

- Branch environments: `ephemeral: true` on a tier gives its environments an instance per branch, named with `--instance` and put in a namespace of its own. Uninstalling a whole stack from an instance tears it down: every release, protected ones too, then the namespace. `generate gitlab-ci --instance` gives a branch's deploy jobs and a stop job GitLab runs when the branch goes, without a checkout.
- [examples/cache](examples/cache): Postgres and Redis in the cluster in dev, qa and each branch's instance, RDS and ElastiCache in prod, and a Liquibase migration versioned as the api's second image.

## v0.6.0 (2026-10-29)

- **Breaking:** tiers in `muster.yaml` hold the release flow: the environments in deploy order, where each takes its changes from (`from`), `production` and `manual`. Environment files keep only what the environment is. A generated pipeline has a stage per tier; a tier named as a GitLab deployment tier sets `deployment_tier`.
- **Breaking:** a stack lists the environments it runs in (`environments` in `stack.yaml`); `stacks/<stack>/<env>.yaml` is optional and holds only what differs.
- `generate gitlab-ci --by cell`: a job per app in each stack.
- A `stack.yaml` that can't be read stops every command.

## v0.5.0 (2026-10-28)

- `generate gitlab-ci --app` is per app without `--by`; jobs get a timeout from their helm calls' timeouts, plus 10 minutes.

## v0.4.0 (2026-10-28)

- `generate gitlab-ci`: a stage per environment, `--stack`, and `--to <env>` to stop at an environment on the chain.

## v0.3.0 (2026-10-22)

- A promotion chain: environments in order, versions reaching one only by promotion from the one before.
- Ship and promote along the chain as a generated pipeline, each job committing its versions file once its deploy passed, through the pipeline's own script (`--commit`).

## v0.2.0 (2026-10-22)

- **Breaking:** the environment, stack and app are named with flags only (`--env`, `--stack`, `--app`), in any order.
- An optional release name prefix and suffix per environment.
- [MATRIX.md](MATRIX.md): matrix deployments as a continuous delivery principle.

## v0.1.0 (2026-10-22)

First release: apps defined once and bound per environment; stacks and their members in deploy order; values composed in layers, each key traceable to its file (`values --explain`); requirements wired to providers; `deploy`, `uninstall`, `restart` and `rollback`, which print their helm or kubectl calls and run them only with `--yes`; image versions per stack and environment, with the tags each environment takes; apps with several images (an init container, a sidecar), each versioned on its own; `disabled` with a reason; `list` with `--names` for pipelines; `generate gitlab-ci`, a GitLab child pipeline for a matrix, and the hello example's GitLab pipeline; SOPS secrets through helm-secrets; charts in an OCI registry or a chart repository; exit code 2 for a wrong command line and 1 for a refusal; [GUIDE.md](GUIDE.md) and [examples/basic](examples/basic); binaries for macOS, Linux and Windows.
