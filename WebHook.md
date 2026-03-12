```YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  name: webhook-access-unauthenticated
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: "system:webhook"
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: "system:unauthenticated"
```

```curl
curl -X POST -k -H "Content-Type: application/json" https://api.cluster-dvdfw.dvdfw.sandbox2448.opentlc.com:6443/apis/build.openshift.io/v1/namespaces/dotnet-renato/buildconfigs/taller-auto-git/webhooks/XXXXXX/generic 
```