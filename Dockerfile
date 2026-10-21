# The CI image for pipelines that run Muster: muster, helm with the
# helm-secrets plugin and sops (for SOPS-encrypted values), kubectl (for
# restarts and checks) and git (to commit version changes).
#
#   docker build -t registry.example.com/platform/muster:1 .
FROM alpine:3.22
ARG TARGETARCH
ARG HELM_VERSION=v4.3.1
ARG KUBECTL_VERSION=v1.37.0
ARG SOPS_VERSION=v3.13.3
ARG HELM_SECRETS_VERSION=4.7.9
# Plugins in a fixed place, so helm finds them whichever user a job runs as
# (helm plugin install itself writes to root's home; they're copied here).
ENV HELM_PLUGINS=/usr/local/share/helm/plugins
RUN apk add --no-cache ca-certificates curl git \
 && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /usr/local/bin --strip-components=1 "linux-${TARGETARCH}/helm" \
 && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl
# sops, checked against its release's checksums.
RUN cd /tmp \
 && curl -fsSLO "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${TARGETARCH}" \
 && curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.checksums.txt" | grep " sops-${SOPS_VERSION}.linux.${TARGETARCH}$" | sha256sum -c - \
 && install -m 0755 "sops-${SOPS_VERSION}.linux.${TARGETARCH}" /usr/local/bin/sops \
 && rm "sops-${SOPS_VERSION}.linux.${TARGETARCH}"
# helm-secrets: the CLI and the secrets:// getter, each checked against its
# author's signature (Helm 4 verifies plugins against a keyring).
RUN apk add --no-cache --virtual .verify gnupg \
 && curl -fsSL https://github.com/jkroepke.gpg | gpg --dearmor > /tmp/helm-secrets.gpg \
 && for p in secrets secrets-getter; do \
      helm plugin install --keyring /tmp/helm-secrets.gpg "https://github.com/jkroepke/helm-secrets/releases/download/v${HELM_SECRETS_VERSION}/${p}-${HELM_SECRETS_VERSION}.tgz" || exit 1; \
    done \
 && mkdir -p "$HELM_PLUGINS" && cp -R /root/.local/share/helm/plugins/. "$HELM_PLUGINS/" \
 && rm -rf /tmp/helm-secrets.gpg /root/.gnupg /root/.local/share/helm/plugins \
 && apk del .verify
# muster, checked against the release checksums.
ARG MUSTER_VERSION=v0.1.0
RUN cd /tmp \
 && curl -fsSLO "https://github.com/britzc/muster/releases/download/${MUSTER_VERSION}/muster-linux-${TARGETARCH}" \
 && curl -fsSL "https://github.com/britzc/muster/releases/download/${MUSTER_VERSION}/SHA256SUMS" | grep " muster-linux-${TARGETARCH}$" | sha256sum -c - \
 && install -m 0755 "muster-linux-${TARGETARCH}" /usr/local/bin/muster \
 && rm "muster-linux-${TARGETARCH}"
