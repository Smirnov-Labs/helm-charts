# Smirnov Labs Helm Charts

Helm charts for [ClusterMind](https://clustermind.ai), AI diagnostics for Kubernetes.

| Chart | Description |
|-------|-------------|
| [clustermind-edge](charts/clustermind-edge/) | The ClusterMind agent. It runs in your cluster and reports to app.clustermind.ai. |

## Install the agent

You need:

- Kubernetes 1.29 or later, managed (EKS, GKE, AKS) or self-hosted. The agent checks Longhorn, Argo CD and cert-manager where they are installed, and needs none of them.
- Linux AMD64 or ARM64 nodes, including mixed clusters. Chart 0.3.2 selects the matching image automatically; see [Node architectures](#node-architectures).
- Outbound HTTPS from the cluster to api.clustermind.ai.
- A default StorageClass, for the agent's 1Gi Redis volume. New EKS clusters have none; see [Storage](#storage).
- Helm 3.8 or later.

1. In the [dashboard](https://app.clustermind.ai), add the cluster under **Clusters** and copy its agent token. The dashboard shows it once.
2. Create the namespace and store the token in it:

   ```bash
   kubectl create namespace clustermind
   kubectl -n clustermind create secret generic clustermind-agent-token --save-config \
     --from-literal=CLUSTER_API_KEY=<agent token>
   ```

   `--save-config` lets you update the Secret later with `kubectl apply`.

3. Install the chart:

   ```bash
   helm install clustermind-edge oci://ghcr.io/smirnov-labs/charts/clustermind-edge \
     --version 0.3.2 \
     --namespace clustermind \
     --set controlPlane.existingSecret=clustermind-agent-token
   ```

Within a minute or two the cluster shows as connected in the dashboard. Scans use your workspace's Anthropic API key, which you set in the dashboard under **Settings**. The agent gets that key and its Slack access from ClusterMind. The chart takes no Anthropic or Slack credentials.

To check on the agent:

```bash
kubectl -n clustermind get pods
kubectl -n clustermind logs statefulset/clustermind-edge -c agent
```

If the log shows `websocket_connection_failed` with `"reason": "unauthorized"`, the Secret doesn't hold the cluster's current token.

The chart won't install into the `default` namespace, or without a token.

### Node architectures

Chart **0.3.2** works on Linux AMD64, ARM64 and mixed clusters with the same
installation command. Both agents select Linux nodes without an architecture
restriction. Kubernetes pulls the matching variant of the multi-platform image
for whichever node runs the pod. Redis also supports both architectures.

The default edge image is the verified build `54eadc9`, from
[claude-k8s commit 54eadc9](https://github.com/Smirnov-Labs/claude-k8s/commit/54eadc928537ee6d0238077de2cb56133e50f69c).
Both architectures passed native runtime and bundled-tool checks. It is pinned
to a commit tag, so chart installs do not follow the mutable `latest` tag.

You can still restrict either agent with `agent.nodeSelector` or
`superAgent.nodeSelector`. Custom image overrides must support the architectures
you allow. Chart 0.3.1 and earlier still default to AMD64-only images.

When upgrading an existing release, remove old `image.tag` and architecture
overrides if you want automatic selection. To discard values retained by earlier
installs, use `--reset-values` and reapply your token, storage and other custom
settings, for example:

```bash
helm upgrade clustermind-edge oci://ghcr.io/smirnov-labs/charts/clustermind-edge \
  --version 0.3.2 --namespace clustermind --reset-values \
  --set controlPlane.existingSecret=clustermind-agent-token
```

### Storage

Redis keeps the agent's approval and investigation state on a 1Gi volume from the cluster's default StorageClass. If the cluster has no default StorageClass, the install stops and says so. Then either name a class:

```bash
--set redis.persistence.storageClass=gp3
```

or keep Redis in memory, which loses that state whenever the pod restarts:

```bash
--set redis.persistence.enabled=false
```

On EKS, volumes also need the Amazon EBS CSI driver add-on.

### Rotate the agent token

After you regenerate the token in the dashboard, update the Secret and restart the agent:

```bash
kubectl -n clustermind create secret generic clustermind-agent-token \
  --from-literal=CLUSTER_API_KEY=<new agent token> \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n clustermind rollout restart statefulset/clustermind-edge
```

### Let the agent make changes

By default the agent can read the cluster and change nothing. It cannot read Secrets.

The super-agent runs changes that someone approved in the dashboard, such as restarting a deployment or cordoning a node. It has broad write access, Secrets included, so it is off by default. To turn it on:

```bash
helm upgrade clustermind-edge oci://ghcr.io/smirnov-labs/charts/clustermind-edge \
  --namespace clustermind \
  --set controlPlane.existingSecret=clustermind-agent-token \
  --set superAgent.enabled=true
```

[rbac-readwrite.yaml](charts/clustermind-edge/templates/rbac-readwrite.yaml) lists everything it can do.

### Upgrade

Run `helm upgrade` with the flags you installed with. Each chart version deploys the agent version in its `appVersion`; set `image.tag` to run a different release.

**From 0.2.0:**

- 0.2.0 made the release own its namespace and later versions don't, so a plain upgrade deletes the namespace and everything in it. Tell Helm to keep it first:

  ```bash
  kubectl annotate namespace <namespace> helm.sh/resource-policy=keep
  ```

- 0.3.0 turns on Redis AOF, and Redis starts empty on the first restart after that. To keep its data, switch AOF on in the running Redis before you upgrade:

  ```bash
  kubectl -n <namespace> exec <release>-clustermind-edge-0 -c redis -- redis-cli config set appendonly yes
  ```

  The pod is `clustermind-edge-0` if you named the release `clustermind-edge`.

### Uninstall

```bash
helm uninstall clustermind-edge --namespace clustermind
kubectl -n clustermind delete pvc redis-data-clustermind-edge-0
kubectl delete namespace clustermind
```

Helm leaves the Redis volume behind, so delete it yourself or keep it for a reinstall.

### Direct Slack mode

Without the control plane, the agent can take Slack events itself. Set `controlPlane.url=""`, the `slack` values, and `ingress` so Slack can reach `/slack/events`. Installs that use app.clustermind.ai don't need any of this.

### Configuration

Every value is in [values.yaml](charts/clustermind-edge/values.yaml). The ones you are most likely to set:

| Value | Default | Meaning |
|-------|---------|---------|
| `controlPlane.existingSecret` | `""` | Secret with the agent token, under the key `CLUSTER_API_KEY` |
| `controlPlane.clusterApiKey` | `""` | The token itself, if you'd rather the chart create the Secret. It then also sits in Helm's release history. |
| `redis.persistence.storageClass` | `""` | StorageClass for the Redis volume. Empty uses the cluster default. |
| `redis.persistence.enabled` | `true` | `false` keeps Redis in memory |
| `superAgent.enabled` | `false` | Run changes approved in the dashboard |
| `agent.nodeSelector` | `kubernetes.io/os: linux` | Nodes the agent can run on; AMD64 and ARM64 are selected automatically |
| `superAgent.nodeSelector` | `kubernetes.io/os: linux` | Nodes the optional super-agent can run on |
| `metrics.serviceMonitor.enabled` | `false` | Create a Prometheus Operator ServiceMonitor |
| `metrics.prometheusRule.enabled` | `false` | Create alert rules, including one for a rejected agent token |

## License

Copyright Smirnov Labs. All rights reserved.
