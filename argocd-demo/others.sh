➜  oc create sa  anyuid-sa
serviceaccount/anyuid-sa created

➜  oc get sa  anyuid-sa -oyaml | kubectl-neat | yq
apiVersion: v1
imagePullSecrets:
  - name: anyuid-sa-dockercfg-zhjw7
kind: ServiceAccount
metadata:
  annotations:
    openshift.io/internal-registry-pull-secret-ref: anyuid-sa-dockercfg-zhjw7
  name: anyuid-sa
  namespace: dotnet-raziel
secrets:
  - name: anyuid-sa-dockercfg-zhjw7


➜  oc adm policy add-scc-to-user anyuid -z anyuid-sa       
clusterrole.rbac.authorization.k8s.io/system:openshift:scc:anyuid added: "anyuid-sa"
