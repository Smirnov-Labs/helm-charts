#!/usr/bin/env bash
# Lints the clustermind-edge chart, renders it, and checks what it renders. CI runs it
# with the oldest Helm the README supports and with the current one. Run it from any
# directory; set HELM to try another Helm binary:
#
#   tests/clustermind-edge.sh
#   HELM=/path/to/helm tests/clustermind-edge.sh
#
# It needs Helm and python3 with PyYAML.
set -euo pipefail
cd "$(dirname "$0")/.."

HELM="${HELM:-helm}"
CHART=charts/clustermind-edge
# Without a cluster, Helm before 3.14 assumes a Kubernetes older than the chart's
# kubeVersion allows and refuses to render. Render for the oldest one the chart supports.
KUBE_VERSION=1.29.0
OUT=$(mktemp -d)
export OUT
trap 'rm -rf "$OUT"' EXIT

template() {
  "$HELM" template clustermind-edge "$CHART" --kube-version "$KUBE_VERSION" "$@"
}

# Each refuse case must be refused with the chart's own message.
refuse() {
  expected="$1"
  shift
  if output=$(template --namespace clustermind "$@" 2>&1); then
    echo "::error::the chart rendered with: $*; it must refuse"
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "::error::the chart refused with: $*; the error lacks: $expected"
    echo "$output"
    exit 1
  fi
}
renders() {
  if ! output=$(template --namespace clustermind "$@" 2>&1); then
    echo "::error::the chart refused: $*; it must render"
    echo "$output"
    exit 1
  fi
}

echo "Checking $CHART with Helm $("$HELM" version --short)"
"$HELM" lint --strict "$CHART" --namespace clustermind -f "$CHART/ci/test-values.yaml"

# helm lint doesn't evaluate the chart's fail checks, so render it too: with the
# CI values, with every optional part on, and once each where it must refuse.
template --namespace clustermind -f "$CHART/ci/test-values.yaml" > /dev/null
template --namespace clustermind -f "$CHART/ci/test-values.yaml" \
  --set superAgent.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.prometheusRule.enabled=true \
  --set redis.persistence.enabled=false \
  --set diagnostics.localFallback.enabled=true > "$OUT/everything-chart.yaml"
template --namespace clustermind -f "$CHART/ci/test-values.yaml" \
  --set metrics.serviceMonitor.enabled=true > "$OUT/monitored-chart.yaml"
template --namespace clustermind -f "$CHART/ci/test-values.yaml" \
  -f "$CHART/ci/arm64-values.yaml" > "$OUT/arm64-chart.yaml"
template --namespace clustermind -f "$CHART/ci/test-values.yaml" \
  --set superAgent.enabled=true > "$OUT/default-chart.yaml"
template --namespace clustermind -f "$CHART/ci/test-values.yaml" \
  --set superAgent.enabled=true \
  --set 'agent.nodeSelector.kubernetes\.io/arch=amd64' \
  --set 'superAgent.nodeSelector.kubernetes\.io/arch=amd64' > "$OUT/amd64-chart.yaml"
python3 - <<'PYTHON'
import os
import yaml
chart = yaml.safe_load(open('charts/clustermind-edge/Chart.yaml'))
expected_image = 'ghcr.io/smirnov-labs/clustermind-edge:' + chart['appVersion']
for name, architecture in [('default', None), ('amd64', 'amd64'), ('arm64', 'arm64')]:
    workloads = [doc for doc in yaml.safe_load_all(open(os.path.join(os.environ['OUT'], name + '-chart.yaml')))
                 if doc and doc.get('kind') in ('StatefulSet', 'Deployment')]
    assert len(workloads) == 2, (name, workloads)
    for workload in workloads:
        pod = workload['spec']['template']['spec']
        selector = pod['nodeSelector']
        assert selector.get('kubernetes.io/arch') == architecture, (name, selector)
        assert selector['kubernetes.io/os'] == 'linux', (name, selector)
        assert any(c['image'] == expected_image for c in pod['containers']), (name, pod)
PYTHON
refuse "clustermind-edge needs its own namespace" --namespace default -f "$CHART/ci/test-values.yaml"
refuse "Set controlPlane.existingSecret (or controlPlane.clusterApiKey)"
# With the super-agent off, Redis listens on localhost and the Service lists the http
# and metrics ports. With it on, Redis requires a password, the Service adds the Redis
# port, and the super-agent has its own executor token.
template --namespace clustermind -f "$CHART/ci/test-values.yaml" > "$OUT/no-super-agent-chart.yaml"
python3 - <<'PYTHON'
import os
import subprocess
import tempfile
import yaml
def docs(path):
    return [d for d in yaml.safe_load_all(open(path)) if d]
def redis_cmd(ds):
    sts = next(d for d in ds if d['kind'] == 'StatefulSet')
    return next(c for c in sts['spec']['template']['spec']['initContainers'] if c['name'] == 'redis')['command']
def edge_service_ports(ds):
    svc = next(d for d in ds if d['kind'] == 'Service' and not d['metadata']['name'].endswith('super-agent'))
    return [p['port'] for p in svc['spec']['ports']]
out = os.environ['OUT']
plain, full = docs(os.path.join(out, 'no-super-agent-chart.yaml')), docs(os.path.join(out, 'default-chart.yaml'))
assert '--bind' in redis_cmd(plain) and '127.0.0.1' in redis_cmd(plain), redis_cmd(plain)
assert '--requirepass' not in redis_cmd(plain), redis_cmd(plain)
assert 6379 not in edge_service_ports(plain), edge_service_ports(plain)
assert '--requirepass' in redis_cmd(full) and '$(REDIS_PASSWORD)' in redis_cmd(full), redis_cmd(full)
assert 6379 in edge_service_ports(full)
deployment = next(d for d in full if d['kind'] == 'Deployment')
env = {e['name']: e for e in deployment['spec']['template']['spec']['containers'][0]['env']}
assert env['EXECUTOR_TOKEN']['valueFrom']['secretKeyRef'] == {'name': 'clustermind-super-agent-token', 'key': 'EXECUTOR_TOKEN'}, env['EXECUTOR_TOKEN']
assert env['REDIS_PASSWORD']['valueFrom']['secretKeyRef']['name'] == 'clustermind-redis-auth'
pod = next(d for d in full if d['kind'] == 'StatefulSet')['spec']['template']['spec']
sidecar = next(c for c in pod['initContainers'] if c['name'] == 'redis')
agent = next(c for c in pod['containers'] if c['name'] == 'agent')
assert {'REDIS_PASSWORD', 'REDISCLI_AUTH'} <= {e['name'] for e in sidecar['env']}, sidecar['env']
assert 'REDIS_PASSWORD' in {e['name'] for e in agent['env']}, agent['env']
for workload in (d for d in full if d['kind'] in ('StatefulSet', 'Deployment')):
    spec = workload['spec']['template']['spec']
    for container in spec.get('initContainers', []) + spec['containers']:
        for e in container.get('env', []):
            assert e['name'] != 'REDIS_URL' or '@' not in e.get('value', ''), 'REDIS_URL of ' + container['name'] + ' contains @'
# While the super-agent runs, Redis starts only with a password of 16 or more
# characters. The command is checked as rendered, then run with a stand-in redis-server.
auth_cmd = redis_cmd(full)
assert auth_cmd[:2] == ['sh', '-c'] and auth_cmd[3] == 'redis-server', auth_cmd
assert '${#REDIS_PASSWORD}' in auth_cmd[2] and '-lt 16' in auth_cmd[2] and 'exec redis-server "$@"' in auth_cmd[2], auth_cmd[2]
assert redis_cmd(plain)[0] == 'redis-server' and not any('REDIS_PASSWORD' in word for word in redis_cmd(plain)), redis_cmd(plain)
stub_dir = tempfile.mkdtemp(dir=out)
stub_out = os.path.join(stub_dir, 'argv')
with open(os.path.join(stub_dir, 'redis-server'), 'w') as stub:
    stub.write('#!/bin/sh\nprintf "%s\\n" "$@" > "$STUB_OUT"\n')
os.chmod(os.path.join(stub_dir, 'redis-server'), 0o755)
def start_redis(password):
    # The kubelet expands $(REDIS_PASSWORD) before it starts the container.
    argv = [word.replace('$(REDIS_PASSWORD)', password) for word in auth_cmd]
    env = dict(os.environ, PATH=stub_dir + os.pathsep + os.environ['PATH'], REDIS_PASSWORD=password, STUB_OUT=stub_out)
    if os.path.exists(stub_out):
        os.remove(stub_out)
    result = subprocess.run(argv, env=env, capture_output=True, text=True)
    return result, os.path.exists(stub_out)
for password in ('', 'x', 'x' * 15):
    result, started = start_redis(password)
    assert result.returncode != 0 and not started and 'at least 16 characters' in result.stderr, ('a password of ' + str(len(password)) + ' characters must stop Redis', result)
result, started = start_redis('x' * 16)
assert result.returncode == 0 and started, ('a password of 16 characters must start Redis', result)
started_with = open(stub_out).read().splitlines()
assert started_with[started_with.index('--requirepass') + 1] == 'x' * 16 and '--appendonly' in started_with, started_with
PYTHON
# Every pod sets the RuntimeDefault seccomp profile, which Pod Security "restricted"
# requires. With metrics.serviceMonitor.enabled, exactly one ServiceMonitor selects each
# Service that has a metrics port, the super-agent's included.
python3 - <<'PYTHON'
import os
import yaml
out = os.environ['OUT']
def docs(name):
    return [d for d in yaml.safe_load_all(open(os.path.join(out, name + '-chart.yaml'))) if d]
for name in ('default', 'amd64', 'arm64', 'no-super-agent', 'everything', 'monitored'):
    for workload in (d for d in docs(name) if d['kind'] in ('StatefulSet', 'Deployment')):
        context = workload['spec']['template']['spec'].get('securityContext', {})
        assert context.get('seccompProfile') == {'type': 'RuntimeDefault'}, (name, workload['metadata']['name'], context)
for name, expected in (('monitored', 1), ('everything', 2)):
    ds = docs(name)
    monitors = [d for d in ds if d['kind'] == 'ServiceMonitor']
    services = [d for d in ds if d['kind'] == 'Service' and any(p['name'] == 'metrics' for p in d['spec']['ports'])]
    assert len(services) == expected and len(monitors) == expected, (name, [d['metadata']['name'] for d in services + monitors])
    for service in services:
        labels = service['metadata']['labels']
        selecting = [m['metadata']['name'] for m in monitors
                     if m['spec']['namespaceSelector']['matchNames'] == [service['metadata']['namespace']]
                     and all(labels.get(k) == v for k, v in m['spec']['selector']['matchLabels'].items())]
        assert len(selecting) == 1, (name, service['metadata']['name'], selecting)
PYTHON
# An upgrade with --reuse-values uses the values of the old release, which hold only
# the keys that release defined; the from_033 flags give the merged values that shape.
values="$CHART/ci/test-values.yaml"
needs_token="superAgent.enabled needs the executor token from the dashboard (Settings, then Cluster connections, then the cluster's Settings tab)"
needs_password="superAgent.enabled needs a Redis password"  # pragma: allowlist secret
from_033=(--set redis.auth=null --set superAgent.executorToken=null
          --set superAgent.existingSecret=null --set superAgent.existingSecretKey=null)
# The values of an upgrade from 0.3.3 render while the super-agent is off.
renders -f "$values" "${from_033[@]}"
refuse "$needs_token" -f "$values" --set superAgent.enabled=true --set superAgent.existingSecret=
refuse "$needs_password" -f "$values" --set superAgent.enabled=true --set redis.auth.existingSecret=
refuse "superAgent.enabled needs the chart's Redis" -f "$values" --set superAgent.enabled=true --set redis.enabled=false
refuse "superAgent.enabled needs controlPlane.url" -f "$values" --set superAgent.enabled=true --set controlPlane.url= --set slack.existingSecret=clustermind-slack
refuse "$needs_token" -f "$values" "${from_033[@]}" --set superAgent.enabled=true
refuse "$needs_password" -f "$values" "${from_033[@]}" --set superAgent.enabled=true --set superAgent.existingSecret=clustermind-super-agent-token
# The super-agent needs edge v1.10.0 or later. An image.tag that starts with an earlier
# version is refused, with or without the v and a suffix. v1.10.0 and later render, and
# so do an empty tag and a tag that is no version. With the super-agent off, any tag renders.
needs_edge="superAgent.enabled needs edge v1.10.0 or later"
for tag in v1.9.7 1.9.7 v1.9.7-rc.1; do
  refuse "$needs_edge" -f "$values" --set superAgent.enabled=true --set "image.tag=$tag"
done
# The message says how to get past it, and that works: a later --set image.tag= replaces
# the earlier tag, including one that --reset-then-reuse-values brings back.
refuse "Add --set image.tag= to the helm command, or set image.tag to v1.10.0 or later." -f "$values" --set superAgent.enabled=true --set image.tag=v1.9.7
renders -f "$values" --set superAgent.enabled=true --set image.tag=v1.9.7 --set image.tag=
for tag in v1.10.0 1.10.0 v1.10.0-rc.1 v1.11.0 latest sha256-abc123 ""; do
  renders -f "$values" --set superAgent.enabled=true --set "image.tag=$tag"
done
renders -f "$values" --set image.tag=v1.9.7
echo "All checks passed with Helm $("$HELM" version --short)"
