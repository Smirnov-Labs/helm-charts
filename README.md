# Smirnov Labs Helm Charts

Helm charts for [ClusterMind](https://clustermind.ai) — AI-powered Kubernetes diagnostics.

## Charts

| Chart | Description |
|-------|-------------|
| [clustermind-edge](charts/clustermind-edge/) | Edge agent for Kubernetes cluster diagnostics |

## Usage

```bash
helm install clustermind-edge oci://ghcr.io/smirnov-labs/charts/clustermind-edge
```

### Quick Start

1. Create a values file with your credentials:

```yaml
anthropic:
  apiKey: "sk-ant-..."

slack:
  botToken: "xoxb-..."
  signingSecret: "..."
  teamId: "T..."
  alertChannel: "C..."

controlPlane:
  url: "https://api.clustermind.ai"
  clusterApiKey: "your-cluster-api-key"
```

2. Install the chart:

```bash
helm install clustermind-edge \
  oci://ghcr.io/smirnov-labs/charts/clustermind-edge \
  -f values.yaml \
  -n clustermind-edge --create-namespace
```

### Using Existing Secrets

If you prefer to manage secrets externally (recommended for production):

```yaml
anthropic:
  existingSecret: "my-anthropic-secret"
  existingSecretKey: "ANTHROPIC_API_KEY"

slack:
  existingSecret: "my-slack-secret"

controlPlane:
  existingSecret: "my-controlplane-secret"
```

See [values.yaml](charts/clustermind-edge/values.yaml) for all configuration options.

### Verifying Image Signatures

All ClusterMind images are signed with [cosign](https://github.com/sigstore/cosign). Verify before deploying:

```bash
cosign verify --key https://raw.githubusercontent.com/Smirnov-Labs/helm-charts/main/cosign.pub \
  ghcr.io/smirnov-labs/clustermind-edge:<tag>
```

Or using the local key from this repo:

```bash
cosign verify --key cosign.pub ghcr.io/smirnov-labs/clustermind-edge:<tag>
```

## License

Copyright Smirnov Labs. All rights reserved.
