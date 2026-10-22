#!/bin/sh
# Keeps the versions files in step with the default branch, for the jobs that
# muster generate gitlab-ci --commit ci/versions.sh writes. Muster never runs
# git; this script is the pipeline's.
#
#   ci/versions.sh pull            start from the latest default branch: an
#                                  earlier job (dev's, say) may have pushed
#   ci/versions.sh push <message>  after the deploy succeeded: commit the
#                                  versions files, take in what was merged
#                                  meanwhile, and push
#
# A job runs push only when its deploy passed, so a versions file records
# only what deployed, and the next environment promotes only what passed.
# Pushing needs a project access token with write_repository, in the masked
# variable DEPLOY_TOKEN. [skip ci] keeps the push from starting a pipeline.
set -eu

case "${1:-}" in
pull)
  git fetch origin "$CI_DEFAULT_BRANCH"
  git checkout -B "$CI_DEFAULT_BRANCH" FETCH_HEAD
  ;;
push)
  git config user.name "$GITLAB_USER_NAME"
  git config user.email "$GITLAB_USER_EMAIL"
  git add stacks/*/*.versions.yaml
  if git diff --cached --quiet; then exit 0; fi
  git commit -m "$2 [skip ci]"
  git fetch origin "$CI_DEFAULT_BRANCH"
  git rebase FETCH_HEAD
  git push "https://oauth2:${DEPLOY_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "HEAD:${CI_DEFAULT_BRANCH}"
  ;;
*)
  echo "usage: $0 pull | push <message>" >&2
  exit 2
  ;;
esac
