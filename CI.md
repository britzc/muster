# muster ci: pipelines

`muster ci` generates the pipelines a CI system runs Muster in: `muster ci gitlab` today, and another CI system would be another `muster ci <system>`. It is a separate binary, `muster-ci`, which `muster ci` runs (beside `muster`, or on the `PATH`).

**It knows the repository only through `muster`.** It reads the release flow from `muster list … --json` and `muster list tiers`, each stack's members from `muster releases --json`, and each job's calls (for its timeout) from the operation's `--json`, one call per environment for all its jobs. It checks a version with a printing-only `muster versions set`, and writes into a branch's stop job the calls `muster uninstall --json` gives. So it makes no `helm` or `kubectl` call of its own, every rule Muster applies holds in a pipeline too, and a name the repository doesn't have, or a version Muster would refuse, fails generating, with Muster's own message, rather than a job.

**Both come from one release.** `muster ci version` shows the two; `muster-ci` refuses a `muster` whose JSON contract (`muster version`) is not the one it reads, and says to install the two from one release.

[README.md](README.md) covers Muster itself: the repository, values, versions and the commands a job runs. [MATRIX.md](MATRIX.md) explains the continuous delivery principles behind the pipelines.

## GitLab child pipelines

A stack deploys in an environment only after it deployed in the environment before ([matrix deployments](README.md#matrix-deployments)). `muster ci gitlab` turns a matrix into a GitLab child pipeline with a job per cell, which [the example pipeline](#the-example-pipeline) runs. Each deploy job `needs` the same stack's job in the environment before, so a failed deploy in qa stops prod:

```console
$ muster ci gitlab --yes --auto           # every stack everywhere; production jobs manual
stages: [dev, qa, prod]
deploy hello in dev:
  stage: dev
  environment: dev
  resource_group: dev
  when: on_success
  timeout: 16m
  script:
    - muster deploy --env dev --stack hello --yes
deploy hello in qa:
  stage: qa
  environment: qa
  resource_group: qa
  when: on_success
  timeout: 16m
  needs: [deploy hello in dev]
  script:
    - muster deploy --env qa --stack hello --yes
…
$ muster ci gitlab                                                           # every deploy, printed only
$ muster ci gitlab --yes --stack hello --auto                                # one stack along the chain
$ muster ci gitlab --yes --app web --tag 1.2.0 --production=false            # a test build of web, in dev
$ muster ci gitlab --yes --app web --tag 1.2.0 --auto --commit ci/versions.sh  # ship web along the chain
$ muster ci gitlab --yes --app web --tag 1.2.0 --auto --commit ci/versions.sh --to qa  # ship web to dev, then qa
$ muster ci gitlab --yes --action promote --commit ci/versions.sh             # promote every stack along the chain
$ muster ci gitlab --yes --action restart --skip local                       # restart every stack, but on a laptop
```

By default a pipeline has a job per stack an environment hosts, and `--by app` one per app in each of those stacks. Every job is one stack's, so the pipeline follows where apps are defined: an app in several stacks has a job in each, moves on in each by itself, and each job sets or promotes the versions of its own stack only. A stage per tier in every case (`tiers` in `muster.yaml`), so all production environments share one stage, while each job still waits only for its own environment before. A tier named after one of GitLab's deployment tiers (`production`, `staging`, `testing`, `development`, `other`) also sets the jobs' `deployment_tier`. It covers every stack and app, or narrows them: `--stack <stack>` to one stack, `--app <app>` to one app (a job per stack that has it, so `--app` implies `--by app`), or both. What is disabled gets no job, an app only gets one where it runs a chart or a mock, and an uninstall from production carries `--confirm`. `--auto` starts the jobs of every environment that isn't manual (`manual` in `muster.yaml`, by default the tier's `production`); a manual job that a later one needs gets `allow_failure: false`, so the later one waits for it. `--tag` and `--chart` ship a version of the named app: with `--commit <script>`, set where the chain starts and promoted from each environment to the next, each job committing once its deploy passed; without it, only where the chain starts and not committed, for testing a build. `--action promote` promotes each environment from the one before, then deploys. `--action rollback --app <app> --tag <older> --to <env>` rolls the app back in that environment alone, with `versions set --confirm <env>` ([Rolling back](README.md#rolling-back)). `--to <env>` stops at an environment: only it and those before it on its chain, so `--tag 1.2.0 --commit … --to dev` sets and commits a version in dev alone, and a later promote takes it on. Without `--yes`, the jobs only print their calls, as every Muster command does, and as a merge request's pipeline wants: they have no GitLab environment, so nothing records a deployment, and they take no `--commit`. A pipeline acts only when `--yes` is written out: then each job's command carries `--yes`, and the job a `timeout`: its helm calls' timeouts added up, since a stack's releases deploy one after another, plus 10 minutes. `muster ci gitlab --help` has every flag. [MATRIX.md](MATRIX.md) explains the continuous delivery principles behind matrix deployments.

## A branch's instance

An [ephemeral environment](README.md#branch-environments) has an instance per branch. `muster ci gitlab` leaves the ephemeral environments out, so main's pipeline never touches them. `muster ci gitlab --instance <name>` covers only them: a deploy job per stack, in GitLab environment `<env>/<instance>` with `on_stop` and `auto_stop_in` (`--auto-stop-in`, default `1 week`), and a stop job per environment, which GitLab runs when the branch is deleted or the time is up, or you run by hand. The stop job holds the `helm` and `kubectl` calls `muster uninstall --json` gives, written out, with `GIT_STRATEGY: none`, so it runs after the branch is gone. Those calls are the ones of the branch's last pipeline, which GitLab keeps as the environment's stop job: each push regenerates them. Change where an ephemeral environment deploys (its kube context or namespace) only once its instances are stopped, or stop them by hand (`muster uninstall --env <env> --stack <stack> --instance <name> --yes`) afterwards, since a stop job generated before the change still points at the old place. `auto_stop_in` bounds how long such a job waits. `--version` passes each override to the deploy jobs, and generating fails when a version is in neither the versions file nor `--version`, so a pipeline never starts a deploy that can't run. A branch's pipeline might have:

```yaml
review-plan:
  stage: plan
  rules: [{ if: $CI_MERGE_REQUEST_IID }]
  script: muster ci gitlab --yes --instance "mr-$CI_MERGE_REQUEST_IID" --version api="$CI_COMMIT_SHORT_SHA" --auto > review.yml
  artifacts: { paths: [review.yml] }
review:
  stage: deploy
  rules: [{ if: $CI_MERGE_REQUEST_IID }]
  trigger: { include: [{ artifact: review.yml, job: review-plan }], strategy: depend }
```

## The example pipeline

[examples/hello/.gitlab-ci.yml](examples/hello/.gitlab-ci.yml) is the hello repository's pipeline. It names no environment, stack or app: every one comes from [`muster list --names`](README.md#list), so adding an environment or a stack to the repository adds it to the pipeline, and disabling one takes it out. It deploys [matrices](#gitlab-child-pipelines): its `plan` job turns the run's inputs into flags for [`muster ci gitlab`](#gitlab-child-pipelines), and runs the child pipeline it prints, a stage per tier and a job per cell.

- **Image:** build it from this repository's [Dockerfile](Dockerfile) (`docker build -t registry.example.com/platform/muster:1 .`). It holds `muster` and `muster-ci`, `helm` with the helm-secrets plugin (checked against its author's signature), `sops` (checked against its release checksums), `kubectl` and `git`.
- **Secrets:** the age key that decrypts the SOPS files, as a GitLab CI/CD variable `SOPS_AGE_KEY_FILE` of type File. It takes precedence over the example's `SOPS_AGE_KEY_FILE`, which points at the demo key.
- **Charts in a registry:** helm needs to be logged in to the registry before a deploy. That is the pipeline's job, done however your platform logs in to it; Muster only names the chart, and depends on nothing but helm. See [Charts in a registry](README.md#charts-in-a-registry).
- **Cluster access:** the job's kubeconfig, from the GitLab agent for Kubernetes (set `cluster.context` to the agent's context, e.g. `platform/agents:qa`) or a `KUBECONFIG` file variable. Muster only names the context.
- **Writing versions back:** a project access token with `write_repository`, in the masked variable `DEPLOY_TOKEN`. The jobs that change versions run [`ci/versions.sh`](examples/hello/ci/versions.sh): `pull` to start from the latest main, and `push`, once the deploy has passed, to commit, take in anything merged meanwhile and push. Muster never runs git; `muster ci gitlab --commit <script>` only names the script in each job.
- **Environments CI can't reach:** list them in the variable `SKIP_ENVIRONMENTS`, e.g. a `local` environment on a laptop.

| Job | When | What it does |
|---|---|---|
| `check` | every merge request and main | `muster validate` |
| `plan`, `matrix` | merge request | Every stack in every environment, production too, as jobs that only print their helm calls (no `--yes`): the same pipeline main runs, so a review sees what the change deploys where. They have no GitLab environment, so nothing records a deployment |
| `plan`, `matrix` | main | Deploys every stack along the chain: each stack in an environment after it deployed in the one before; dev and qa right away, prod as manual jobs |
| `plan`, `matrix` | Run pipeline | What the inputs choose, as manual jobs (below) |
| `plan`, `matrix` | triggered by an app's pipeline with `APP`, and `TAG` (optionally with `DIGEST`), `CHART` (the version of its chart in a registry) or both | Ships it: `versions set` in dev, deploy, commit and push (`[skip ci]`); then promote to qa, deploy, commit; prod waits for a person. A deploy that fails commits nothing and stops what comes after it. `TO` stops it at an environment, e.g. `TO=dev` |
| `plan`, `matrix` | triggered with `ACTION=rollback`, `APP`, `TAG` (the older version, or `CHART`) and `TO` (the environment) | Rolls back: one job in `TO` that runs `versions set --confirm <TO>`, deploys, and commits once the deploy passed. In a manual environment such as prod, a person starts the job |
| `plan`, `matrix` | the pipelines API with the same inputs as Run pipeline, from another system such as a customer app | What the inputs choose; jobs start themselves except in manual environments |
| `plan`, `matrix` | a pipeline schedule that sets the `action` input to `promote` | Promotes along the chain on a schedule, e.g. nightly into qa: each environment's jobs start themselves unless it is manual |

**Only main deploys to every environment.** A pipeline run by hand from another branch offers only the non-production environments (`muster list environments --production=false`), for testing a branch. Protect the production environments in GitLab to enforce it there too; with required approvals, their jobs wait for an approver.

**Run pipeline** asks for an `action` (deploy, uninstall, restart, promote or rollback), optionally one `stack`, one `app` or both (otherwise `deploy` picks a job per stack or per app in each stack), and for an app optionally a `version`:

| Choice | Child pipeline |
|---|---|
| `stack` | A stage per tier, a job per stack each environment hosts: `muster <action> --env <env> --stack <stack> --yes` |
| `app`, no name | A stage per tier, a job per app in each stack: `muster <action> --app <app> --env <env> --stack <stack> --yes` |
| a `stack` named | A stage per tier, a job in each environment that hosts the stack (per app in it with `app`) |
| an `app` named | A stage per tier, a job per stack that has the app in each environment; with a `stack` too, only that stack's |
| an `app` and a `version` (deploy only) | A job in dev, where the chain starts, first running `muster versions set <app>=<version> … --write` (the app's image named `app` when it has several). The change stays in the job and is not committed: for testing a build |
| `promote` | A job per stack (or app in a stack) in every environment with a `from`, each after the one before: `muster versions promote`, deploy, commit once it passed |
| `rollback`, with an `app`, a `version` and `to` | A job in `to`: `muster versions set <app>=<version> --confirm <to>`, deploy, commit once it passed ([Rolling back](README.md#rolling-back)) |

An app only gets a job where it is a chart or a mock (`--mode helm,mock`), so no job does nothing. Start one job, several, or a whole stage with Run all manual. A deploy job waits for the same stack's (or the same app's in that stack) job in the environment before, and a `resource_group` per environment queues two jobs in the same one. Uninstalling or rolling back in a production environment adds `--confirm <env>`: starting the job is the confirmation. Each job's `timeout` is its helm calls' timeouts added up, plus 10 minutes, since a stack's releases deploy one after another. Without a `version`, a job deploys the versions the repository records.
