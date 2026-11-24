# Command reference

Every command and flag of `muster` and `muster ci`, as `--help` prints them. It is generated from the binaries' own help, so it always matches the binaries of the same release.

How the commands fit together is in [README.md](README.md) (Muster) and [CI.md](CI.md) (pipelines); the day-to-day tasks are in [GUIDE.md](GUIDE.md).

## muster

<!-- generated: muster -->
### `muster`

```text
muster: define apps once, bind them per environment, and get what Helm needs.

Every command reads the repository and prints. deploy, uninstall, restart and
rollback print the helm or kubectl calls they would make, and run them only
with --yes.

Every command that selects releases takes the same form, in any order:
  muster <command> --env <env> --stack <stack> [--app <app>]
--stack can be repeated, or replaced by --all-stacks for every stack <env> hosts.
Without --app, every member of the stack. In an ephemeral environment, which has
an instance per branch, --instance <name> names the instance. Short forms: -e,
-s, -a, -i, and -t for --tag.

Exit codes: 2 when the command line is wrong (an unknown command or flag, a
missing, conflicting or malformed one, or a name the repository doesn't have);
1 when the repository has a problem or refuses the change, or helm or kubectl
failed; 3 when versions promote --exit-unchanged has nothing new to promote.

Usage:
  muster [command]

Available Commands:
  ci          Generate the pipelines a CI system runs Muster in (muster-ci): muster ci gitlab
  deploy      Deploy the releases with helm, in order
  list        The environments, stacks or apps, and whether each is disabled
  releases    The releases, in deploy order, with their parameters
  restart     Restart the releases' workloads with kubectl, in order
  rollback    Roll the releases back with helm, in reverse order
  uninstall   Remove the releases with helm, in reverse order
  validate    Check every file, and every stack in every environment that hosts it
  values      The values one release gets, as Helm reads them
  version     The release, and the JSON contract muster-ci reads
  versions    Each release's images, the version each gets, and where it comes from

Flags:
      --repo string   repository, or any folder inside it (default ".")

Use "muster [command] --help" for more information about a command.
```

### `muster deploy`

```text
Prints the helm calls, one per release, and runs them only with --yes:
one after the other, from the repository root, stopping at the first that
fails. A deploy passes each release's values to helm on stdin.

External members, and every release in a gitops environment, get no call,
only a "# skip" line with the reason.

Usage:
  muster deploy --env <env> --stack <stack> [-a <app>] [flags]

Examples:
  muster deploy --env qa --stack customer-platform         # print the helm calls
  muster deploy --env qa --stack customer-platform --yes   # run them
  muster deploy --app payments --env qa --all-stacks --yes # one app, in every stack that has it

Flags:
      --all-stacks            every stack the environment hosts
  -a, --app string            the app; without one, every member
  -e, --env string            the environment
  -i, --instance string       the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                  the calls as a JSON array, each with its argv (or why it gets none) and, for a deploy, the values helm reads on stdin; runs nothing
  -s, --stack stringArray     a stack the environment hosts (repeatable)
      --version stringArray   in an instance of an ephemeral environment: <app>[.<image>]=<tag>[@<digest>] over its versions file, for this run only (repeatable)
      --yes                   run the calls instead of printing them

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster list`

```text
The environments, stacks or apps, and whether each is disabled: to know what to
select, and to build pipeline choices from.

A table says for each whether it is disabled, and why: its environment, its
stack in an environment or its member entry says disabled: true. --names
prints only the ones not disabled, one per line, for scripts and pipelines, so
they never offer what is disabled. --json gives name, disabled and reason.

For environments, the table and --json also give each one's tier and kube
context (cluster.context in its environment file), and --json its from,
production, ephemeral, manual and gitops. --get prints one of these for the
environment --env names, alone on a line, for a pipeline step that needs it
before Muster runs, such as kubectl or a cloud CLI writing the kubeconfig. It
fails when the environment has no value for it, so a script never runs kubectl
with an empty context.

Environments come in deploy order: each after the environment it promotes
from (its from in muster.yaml), and otherwise tier by tier, then
by name. Apps of one stack come in its member order.

The filters narrow to where an environment hosts a stack with the app: --env for
an environment, --stack for a stack, --app for an app, --mode for the
app's mode there (helm, mock or external), and --versioned for where it takes
versions (its own chart, with images named in app.yaml or the chart in a
registry). For environments, --production
gives only those whose tier has production: true, and --production=false the
others; --ephemeral those whose tier has ephemeral: true, which take an
instance per branch, and --ephemeral=false the others. A name is
disabled only when it is disabled in every place the filters select.

Usage:
  muster list environments|stacks|apps [flags]
  muster list [command]

Examples:
  muster list environments                          # each, and whether and why it is disabled
  muster list environments --names                  # the ones not disabled, for a pipeline
  muster list environments --ephemeral=false --names # those without instances
  muster list environments --env prod --get context  # prod's kube context, alone
  muster list stacks --app web --env qa             # the stacks in qa that have web
  muster list apps --stack hello                    # its members, in deploy order
  muster list apps --env qa --mode helm,mock --json # what deploying in qa installs
  muster list stacks --app web --env qa --versioned # where versions set web=… works in qa

Available Commands:
  apps         The apps, and whether each is disabled
  environments The environments, and whether each is disabled
  stacks       The stacks, and whether each is disabled
  tiers        The tiers, in deploy order: a pipeline stage each

Global Flags:
      --repo string   repository, or any folder inside it (default ".")

Use "muster list [command] --help" for more information about a command.
```

### `muster list apps`

```text
The apps, and whether each is disabled

Usage:
  muster list apps [-e <env>] [-s <stack>] [--mode <mode>] [--versioned] [flags]

Flags:
  -e, --env string          only what this environment hosts
      --json                a JSON array of name, disabled and reason
      --mode strings        only where the app is in this mode: helm, mock or external (repeatable, or comma-separated)
      --names               only the names of the ones not disabled, one per line, for scripts
  -s, --stack stringArray   only in this stack (repeatable)
      --versioned           only where the app runs its own chart and names images or has its chart in a registry: where versions set can change its versions

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster list environments`

```text
The environments, and whether each is disabled

Usage:
  muster list environments [-e <env>] [-a <app>] [-s <stack>] [--mode <mode>] [--versioned] [--production] [--ephemeral] [--get <field>] [flags]

Flags:
  -a, --app string          only where this app is
  -e, --env string          only this environment
      --ephemeral           only ephemeral environments; --ephemeral=false for only the others
      --get string          with --env, print only this of it: context, ephemeral, from, gitops, manual, production, tier
      --json                a JSON array of name, disabled, reason, tier, from, production, ephemeral, manual, gitops and context
      --mode strings        only where the app is in this mode: helm, mock or external (repeatable, or comma-separated)
      --names               only the names of the ones not disabled, one per line, for scripts
      --production          only production environments; --production=false for only the others
  -s, --stack stringArray   only in this stack (repeatable)
      --versioned           only where the app runs its own chart and names images or has its chart in a registry: where versions set can change its versions

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster list stacks`

```text
The stacks, and whether each is disabled

Usage:
  muster list stacks [-a <app>] [-e <env>] [--mode <mode>] [--versioned] [flags]

Flags:
  -a, --app string     only where this app is
  -e, --env string     only what this environment hosts
      --json           a JSON array of name, disabled and reason
      --mode strings   only where the app is in this mode: helm, mock or external (repeatable, or comma-separated)
      --names          only the names of the ones not disabled, one per line, for scripts
      --versioned      only where the app runs its own chart and names images or has its chart in a registry: where versions set can change its versions

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster list tiers`

```text
The tiers muster.yaml lists, in its order, which is deploy order: a
generated pipeline has a stage per tier. --json gives each one's name,
production and ephemeral.

Usage:
  muster list tiers [flags]

Flags:
      --json   a JSON array of name, production and ephemeral

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster releases`

```text
The releases, in deploy order, with everything needed to act on them.
External members are included, marked by their mode. --json gives one object
per release, for scripts and pipelines.

Usage:
  muster releases --env <env> --stack <stack> [-a <app>] [flags]

Examples:
  muster releases --env qa --stack customer-platform
  muster releases --app payments --env qa --all-stacks --json

Flags:
      --all-stacks            every stack the environment hosts
  -a, --app string            the app; without one, every member
  -e, --env string            the environment
  -i, --instance string       the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                  JSON instead of a table
  -s, --stack stringArray     a stack the environment hosts (repeatable)
      --version stringArray   in an instance of an ephemeral environment: <app>[.<image>]=<tag>[@<digest>] over its versions file, for this run only (repeatable)

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster restart`

```text
Prints a kubectl rollout restart per release, for its deployments,
statefulsets and daemonsets with the label app.kubernetes.io/instance=<release>,
and runs them only with --yes, stopping at the first that fails. In an
environment with helm.wait, each restart is followed by a kubectl rollout
status that waits up to helm.timeout.

External members, disabled ones, and every release in a gitops environment,
get no call, only a "# skip" line with the reason. A workload without the
label is not restarted, and kubectl reports "No resources found".

Usage:
  muster restart --env <env> --stack <stack> [-a <app>] [flags]

Examples:
  muster restart --app web --env qa --stack hello --yes # one app
  muster restart --env qa --stack hello --yes           # every member, in order

Flags:
      --all-stacks          every stack the environment hosts
  -a, --app string          the app; without one, every member
  -e, --env string          the environment
  -i, --instance string     the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                the calls as a JSON array, each with its argv (or why it gets none) and, for a deploy, the values helm reads on stdin; runs nothing
  -s, --stack stringArray   a stack the environment hosts (repeatable)
      --yes                 run the calls instead of printing them

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster rollback`

```text
Prints a helm rollback per release, in reverse member order, and runs them
only with --yes, stopping at the first that fails. Without --to, each release
goes back to its previous revision; --to <revision> names one, for a single
release ('helm history <release>' lists them).

A rollback changes the cluster only: the repository still records what was
rolled back, so the next deploy brings it back. It's for a person in a hurry.
The rollback that lasts is in the repository: 'muster versions set
<app>=<version> --env <env> --stack <stack> --confirm <env> --write', committed
and deployed. A generated pipeline's rollback job does exactly that.

External members, and every release in a gitops environment, get no call,
only a "# skip" line with the reason.

Usage:
  muster rollback --env <env> --stack <stack> [-a <app>] [flags]

Examples:
  muster rollback --app web --env prod --stack hello --yes        # web, to its previous revision
  muster rollback --app web --env prod --stack hello --to 3 --yes # web, to revision 3
  muster rollback --env qa --stack hello --yes                    # every member, last first

Flags:
      --all-stacks          every stack the environment hosts
  -a, --app string          the app; without one, every member
  -e, --env string          the environment
  -i, --instance string     the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                the calls as a JSON array, each with its argv (or why it gets none) and, for a deploy, the values helm reads on stdin; runs nothing
  -s, --stack stringArray   a stack the environment hosts (repeatable)
      --to string           the revision to go back to, for a single release (default: the previous one)
      --yes                 run the calls instead of printing them

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster uninstall`

```text
Prints the helm calls, one per release, in reverse member order, and runs
them only with --yes, stopping at the first that fails. An uninstall from a
production environment also needs --confirm <env>.

External members, and every release in a gitops environment, get no call,
only a "# skip" line with the reason. A protected release never gets an
uninstall, and there is no flag to change that, except in a teardown.

A teardown is an uninstall of a whole stack in an instance of an ephemeral
environment (--instance): it removes every release, protected ones too, then
deletes the instance's namespace with kubectl, unless a member is disabled.

Usage:
  muster uninstall --env <env> --stack <stack> [-a <app>] [flags]

Examples:
  muster uninstall --env qa --stack customer-platform --yes
  muster uninstall --env prod --stack customer-platform --yes --confirm prod
  muster uninstall --env temp --stack shop --instance pr-142 --yes # tear down a branch's instance

Flags:
      --all-stacks          every stack the environment hosts
  -a, --app string          the app; without one, every member
      --confirm string      the production environment being changed (required to uninstall from one)
  -e, --env string          the environment
  -i, --instance string     the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                the calls as a JSON array, each with its argv (or why it gets none) and, for a deploy, the values helm reads on stdin; runs nothing
  -s, --stack stringArray   a stack the environment hosts (repeatable)
      --yes                 run the calls instead of printing them

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster validate`

```text
Check every file, and every stack in every environment that hosts it

Usage:
  muster validate [flags]

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster values`

```text
The values one release gets: every layer merged, with a comment on every key
naming the file that set it. Helm ignores the comments, so the output is the
file for helm -f. --explain adds the chart's defaults and a header per
release, for review; with --explain --app is optional.

Usage:
  muster values --app <app> --env <env> --stack <stack> [flags]

Examples:
  muster values --app payments --env qa --stack customer-platform
  muster values --env qa --stack customer-platform --explain
  muster values --app payments --env qa --stack customer-platform | helm template x charts/payments -f -

Flags:
      --all-stacks            every stack the environment hosts
  -a, --app string            the app; without one, every member
  -e, --env string            the environment
      --explain               add the chart's defaults and a header per release
  -i, --instance string       the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
  -s, --stack stringArray     a stack the environment hosts (repeatable)
      --version stringArray   in an instance of an ephemeral environment: <app>[.<image>]=<tag>[@<digest>] over its versions file, for this run only (repeatable)

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster version`

```text
The release, and the JSON contract muster-ci reads

Usage:
  muster version [flags]

Flags:
      --json   version and contract as JSON

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster versions`

```text
Each release's images (named in app.yaml), the version each gets, where it
comes from (the stack's versions file, a values file, or the chart's default).
set and promote change the versions file.

Usage:
  muster versions --env <env> --stack <stack> [-a <app>] [flags]
  muster versions [command]

Available Commands:
  promote     Copy image versions from another environment into one stack's versions file
  set         Set image versions in one stack's versions file

Flags:
      --all-stacks          every stack the environment hosts
  -a, --app string          the app; without one, every member
  -e, --env string          the environment
  -i, --instance string     the instance of an ephemeral environment, such as a branch's slug: its namespace's {instance}
      --json                JSON instead of a table
  -s, --stack stringArray   a stack the environment hosts (repeatable)

Global Flags:
      --repo string   repository, or any folder inside it (default ".")

Use "muster versions [command] --help" for more information about a command.
```

### `muster versions promote`

```text
Copies image versions from another environment into one stack's versions
file. An environment with a from takes them only from that
environment, which --from defaults to; without one, name it with
--from.

Usage:
  muster versions promote --env <env> --stack <stack> [--from <env>] [-a <app>...] [flags]

Examples:
  muster versions promote --env prod --stack customer-platform --write   # from prod's from
  muster versions promote --env prod --stack customer-platform --app payments --write
  muster versions promote --from qa --env prod --stack customer-platform --write

Flags:
  -a, --app stringArray     only this app (repeatable); without one, every app
  -e, --env string          the environment
      --exit-unchanged      exit 3 when there is nothing new to promote (the file would not change), so a job deploys only what a promotion changed
      --from string         the environment to copy versions from (default: the environment's from in muster.yaml)
  -s, --stack stringArray   the stack whose versions file changes
      --write               update the versions file (the only file Muster writes)

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster versions set`

```text
Sets image versions in one stack's versions file. <app>=<tag> sets the app's
only image, or the one named app when it has several (beside an init container
or a sidecar, say); <app>.<image>=<tag> sets any image the app names in its
app.yaml, and <app>.chart=<version> the version of its chart in a registry.

Only an environment without a from (muster.yaml) takes versions set directly: the
first of a chain, such as dev. Every later one takes them by promote, from the
environment before it. To set one there anyway, such as rolling prod back to
the version it ran before, name the environment with --confirm <env>: the
version then skips the chain, and the commit of the file records it.

In an ephemeral environment, set is the only way to change the versions file;
a deploy overrides it with --version for one run.

Usage:
  muster versions set <app>[.<image>]=<tag>[@<digest>]... --env <env> --stack <stack> [flags]

Examples:
  muster versions set payments=1.4.2 --env dev --stack customer-platform --write
  muster versions set web.sidecar=1.37.0 --env dev --stack hello --write
  muster versions set web=1.0.0 --env prod --stack hello --confirm prod --write  # roll prod back

Flags:
      --confirm string      the environment being changed: sets a version where it would otherwise come only by promote, such as a rollback
  -e, --env string          the environment
  -s, --stack stringArray   the stack whose versions file changes
      --write               update the versions file (the only file Muster writes)

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```
<!-- /generated: muster -->

## muster ci

<!-- generated: muster ci -->
### `muster ci`

```text
muster ci: generate the pipelines a CI system runs Muster in.

Each job runs a muster command; Muster makes every helm and kubectl call, and
applies every rule. muster ci reads the repository only through the muster
CLI, so it never acts on a cluster, or on a repository, itself.

Exit codes: 2 when the command line is wrong, or names what the repository
doesn't have; 1 when the repository has a problem, or Muster refuses.

Usage:
  muster ci [flags]
  muster ci [command]

Available Commands:
  gitlab      A GitLab child pipeline for a matrix: a stage per tier, a job per stack or app
  help        Help about any command
  version     The release of muster-ci, and of the muster it runs

Flags:
      --repo string   repository, or any folder inside it (default ".")

Use "muster ci [command] --help" for more information about a command.
```

### `muster ci gitlab`

```text
Prints a GitLab child pipeline that runs a muster command for each stack of a
matrix: a stage per tier (tiers in muster.yaml, in their order), and in it a
job per stack each of the tier's environments hosts (the default), or per app
in each of those stacks (--by app). Every job is one stack's, so the pipeline
follows where apps are defined: an app in several stacks has a job in each,
and moves on in each by itself. --stack and --app narrow the jobs, alone or
together; an app named (--app) implies --by app. An app gets a job only where
it runs a chart or a mock.

Each job runs a muster command, and Muster makes every helm and kubectl call:
muster ci reads the repository only through it (muster list, releases,
versions and the operations' --json), so a name it doesn't have, or a
version it would refuse, fails generating, not a job.

Without --yes, the jobs only print their helm and kubectl calls, as every
muster command does: a pipeline that shows what it would do, e.g. in a merge
request. Such jobs have no environment, so GitLab records no deployment, and
commit nothing, so --commit needs --yes. With --yes, each job's command
carries --yes, so it runs the calls, and the job a timeout: its calls' helm
timeouts added up, plus 10 minutes for the rest. A pipeline only changes
anything when --yes is written out.

--to <env> stops the pipeline at an environment: only it and the ones it
promotes from (from, in muster.yaml), back to the start of its chain.

What is disabled gets no job, as with muster list --names. Every job is manual
unless --auto, which starts the jobs of environments that aren't manual
(manual in muster.yaml: the environment's, by default its tier's, by default
the tier's production). An uninstall or a rollback in a production
environment carries --confirm, so starting the job confirms it.
Each job that runs its calls has the environment as its GitLab environment
and resource_group; when the tier's name is one of GitLab's deployment tiers
(production, staging, testing, development, other), it is the environment's
deployment_tier too.

A deploy job needs the job for the same stack (or app) in the environment it
promotes from (from, in muster.yaml), or the nearest one before that the pipeline
has, so it starts only once that one has succeeded. That environment's tier
can't come after this one's: GitLab can't wait for a later stage (P006). A manual job that another
needs has allow_failure: false, so the one after it waits for it to run.

Ephemeral environments (ephemeral: true on their tier) take an instance per
branch, and only a pipeline with --instance <name> covers them; every other
pipeline leaves them out. With --instance, the jobs are a job per stack of each
ephemeral environment, running with --instance, in GitLab environment
<env>/<instance>. A deploy pipeline adds a stop job per environment, which GitLab
runs when the branch is deleted (on_stop), or after --auto-stop-in (default 1
week): it tears the instance down with the calls muster uninstall --json
gives, written into the job, so it needs no checkout of the deleted branch
(GIT_STRATEGY: none). An instance runs its environment's versions file, and --version (repeatable) overrides one, such as the branch's build:
each job passes it to muster deploy. Generating fails when a version is in
neither.

Versions, with --commit <script>: a job that changes a versions file runs
'<script> pull' first, to start from the latest default branch, and
'<script> push <message>' once its deploy has succeeded, to commit the file and
push it. Muster never runs git: the script is the pipeline's. So a versions
file only ever records what deployed, and the next environment promotes only
what passed in the one before.

  --tag/--chart  ship a new version of the named app: set it where the chain
                 starts, then promote it from environment to environment. The
                 app gets a job where it takes versions. Without --commit,
                 only where the chain starts, and nothing is committed: for
                 testing a build.
  --action promote
                 promote each environment's versions from the one before,
                 then deploy: a job per stack (or app, or cell) in every
                 environment with a from. Needs --commit.
  --action rollback
                 take the named app back to an older version (--tag or
                 --chart) in one environment (--to), then deploy: muster
                 versions set --confirm <env> in each stack there that runs
                 the app's own chart. Needs --commit. A promote into the
                 environment later copies what the one before runs, so roll
                 that one back too, or ship a fix through the chain.

A rollback here is the one that lasts: the repository records it. muster
rollback, helm's previous revision in the cluster only, is for a person at a
terminal, and has no pipeline job.

Usage:
  muster ci gitlab [-s <stack>] [-a <app>] [--by stack|app] [--action <action>] [-t <tag>] [--chart <version>] [--commit <script>] [--to <env>] [--yes] [flags]

Examples:
  muster ci gitlab                                     # every deploy, printed only (a merge request)
  muster ci gitlab --yes --auto                        # main: every stack everywhere
  muster ci gitlab --yes --stack hello --auto          # one stack, along the chain
  muster ci gitlab --yes --app web --tag 1.2.0         # web, at a test build, in dev
  muster ci gitlab --yes --app web --tag 1.2.0 --auto --commit ci/versions.sh          # ship web through the chain
  muster ci gitlab --yes --app web --tag 1.2.0 --auto --commit ci/versions.sh --to qa  # ship web to dev, then qa
  muster ci gitlab --yes --action promote --commit ci/versions.sh                      # promote every stack
  muster ci gitlab --yes --action promote --env prod --auto --approve prod --commit ci/versions.sh  # a release train's run: prod from qa, by itself
  muster ci gitlab --yes --action rollback --app web --tag 1.0.0 --to prod --commit ci/versions.sh  # web back to 1.0.0 in prod
  muster ci gitlab --yes --stack hello --app web --tag 1.2.0 --commit ci/versions.sh  # ship web in hello only
  muster ci gitlab --yes --action restart --production=false  # restart every stack, off main
  muster ci gitlab --yes --instance "$CI_COMMIT_REF_SLUG" --version api="$CI_COMMIT_SHORT_SHA" --auto  # the branch's instance, with its api

Flags:
      --action string         the command each job runs: deploy, uninstall, restart, promote or rollback (versions, then deploy) (default "deploy")
  -a, --app stringArray       only this app: a job per environment that deploys it
      --approve string        with --auto: this manual environment's jobs start themselves too; naming it approves them, as a schedule does
      --auto                  start the jobs of environments that aren't manual without waiting (manual in muster.yaml, by default the tier's production)
      --auto-stop-in string   with --instance: when GitLab stops the instance's environments if nothing deploys to them (default "1 week")
      --by string             a job per stack an environment hosts (stack, the default), or per app in each of those stacks (app; --app implies it)
      --chart string          with --app: the version of its chart in a registry to ship, or roll back to
      --commit string         the pipeline's script that pulls the default branch before a versions change and commits and pushes it after the deploy
  -e, --env string            only this environment, such as the one a release train promotes into
      --image string          the jobs' image, e.g. $CI_JOB_IMAGE
  -i, --instance string       only the ephemeral environments, for this instance of them, such as the branch's slug
      --production            only production environments; --production=false for only the others
      --skip stringArray      an environment the pipeline never reaches (repeatable)
  -s, --stack stringArray     only this stack: a job per environment that hosts it
  -t, --tag string            with --app: the tag[@digest] to ship, or roll back to (the app's image named app when it has several)
      --to string             only this environment and the ones before it on its chain (from, in muster.yaml)
      --version stringArray   with --instance: <app>[.<image>]=<tag>[@<digest>] over the environment's versions file, for its deploys (repeatable)
      --yes                   jobs run their helm and kubectl calls; without it, they only print them

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```

### `muster ci version`

```text
The release of muster-ci, and of the muster it runs

Usage:
  muster ci version [flags]

Global Flags:
      --repo string   repository, or any folder inside it (default ".")
```
<!-- /generated: muster ci -->
