# **Workshop: CI/CD Completo con OpenShift Pipelines y GitOps**

### **Preparación: Repositorios en GitHub**

1. **Repositorio de Código Fuente (app-source)**  
   Crea un archivo Dockerfile en la raíz:

```shell
FROM nginx:alpine

# Agregamos nuestra página web
RUN echo "<h1>Hola from OpenShift CI/CD Pipeline!</h1>" > /usr/share/nginx/html/index.html

# Exponemos el nuevo puerto
EXPOSE 80
```

   

```shell
FROM nginx:alpine

# Agregamos nuestra página web
RUN echo "<h1>Hola from OpenShift CI/CD Pipeline!</h1>" > /usr/share/nginx/html/index.html

# Dar permisos a los directorios que NGINX necesita modificar
RUN chmod -R 777 /var/cache/nginx /var/run /var/log/nginx /etc/nginx/conf.d

# Cambiar la configuración por defecto de NGINX para que escuche en el puerto 8080 (no privilegiado)
RUN sed -i 's/listen  *80;/listen 8080;/g' /etc/nginx/conf.d/default.conf

# Exponemos el nuevo puerto
EXPOSE 8080
```

   

2. **Repositorio de GitOps (app-gitops)**  
   Crea un archivo deployment.yaml en la raíz:

```javascript
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: my-app
  name: my-app
spec:
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      deployment: my-app
  template:
    metadata:
      labels:
        deployment: my-app
    spec:
      containers:
      - image: image-registry.openshift-image-registry.svc:5000/cicd-tu-nombre/my-app:latest
        imagePullPolicy: IfNotPresent
        name: my-app
        ports:
        - containerPort: 8080
          protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: my-app
  name: my-app
spec:
  ports:
  - name: 8080-tcp
    port: 8080
  selector:
    deployment: my-app
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  labels:
    app: my-app
  name: my-app
spec:
  host: ''
  port:
    targetPort: 8080-tcp
  to:
    kind: Service
    name: my-app
    weight: 100
  wildcardPolicy: None
```

---

### **Paso 1: Configuración del Project, Tasks y Permisos**

Inicia sesión en tu **Cluster** y prepara el entorno.

```shell
oc login -u <tu-usuario> -p <tu-password> <url-del-cluster>
oc new-project cicd-tu-nombre
```

**1.1 Instalar Tasks del Catálogo**

En lugar de usar ClusterTasks (que están deprecadas), instalamos las **Tasks** oficiales localmente en nuestro **Project**:

```shell
oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml

oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.6/buildah.yaml
```

**1.2 Configurar Credenciales de GitHub**

Crea un *Personal Access Token* (PAT) en GitHub con permisos de repo (lectura y escritura). Crea el archivo github-secret.yaml:

```javascript
apiVersion: v1
kind: Secret
metadata:
  name: github-auth
  annotations:
    tekton.dev/git-0: https://github.com
type: kubernetes.io/basic-auth
stringData:
  username: <tu-usuario-de-github>
  password: <TU-TOKEN-PAT-CON-PERMISOS-REPO>
```

Aplícalo:

```shell
oc apply -f github-secret.yaml
```

**1.3 Asociar el Secret y otorgar privilegios al ServiceAccount**

Vamos a inyectar el **Secret** al **ServiceAccount** pipeline (creado por defecto) y darle permisos para ejecutar contenedores privilegiados (necesario para buildah).

Crea patch-sa.yaml:

```javascript
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline
  namespace: cicd-tu-nombre
secrets:
  - name: github-auth
```

Aplica el parche y añade el **SCC**:

```shell
oc apply -f patch-sa.yaml
oc adm policy add-scc-to-user privileged -z pipeline -n cicd-tu-nombre
```

---

### **Paso 2: Almacenamiento y Custom Task**

**2.1 Crear el PersistentVolumeClaim (PVC)**

Crea workspace-pvc.yaml para compartir archivos entre los pasos del **Pipeline**:

```javascript
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pipeline-workspace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Aplícalo: oc apply \-f workspace-pvc.yaml

**2.2 Custom Task para GitOps**

Crea update-gitops-task.yaml para actualizar el manifest:

```javascript
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: update-gitops-repo
spec:
  workspaces:
    - name: source
  params:
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
  steps:
    - name: git-update
      image: alpine/git:v2.36.2
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -e
        git clone $(params.gitops-repo-url) gitops-repo
        cd gitops-repo
        
        sed -i 's|image: .*|image: image-registry.openshift-image-registry.svc:5000/cicd-tu-nombre/my-app:$(params.image-tag)|g' deployment.yaml
        
        git config user.email "pipeline@openshift.com"
        git config user.name "OpenShift Pipeline"
        
        git add deployment.yaml
        git commit -m "Update image tag to $(params.image-tag)"
        git push origin main
```

Aplícalo: oc apply \-f update-gitops-task.yaml

---

### **Paso 3: Definir y Ejecutar el Pipeline**

**3.1 Crear el Pipeline**

Crea pipeline.yaml. Nota que hemos añadido retries: 1 a la última tarea para mayor resiliencia en caso de fallos de red con GitHub:

```javascript
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-and-update-gitops
spec:
  workspaces:
    - name: shared-workspace
  params:
    - name: source-repo-url
      type: string
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.source-repo-url)
          
    - name: build-image
      taskRef:
        name: buildah
      runAfter:
        - fetch-source
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: IMAGE
          value: image-registry.openshift-image-registry.svc:5000/cicd-tu-nombre/my-app:$(params.image-tag)
          
    - name: update-gitops
      taskRef:
        name: update-gitops-repo
      runAfter:
        - build-image
      retries: 1
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: gitops-repo-url
          value: $(params.gitops-repo-url)
        - name: image-tag
          value: $(params.image-tag)
```

Aplícalo: oc apply \-f pipeline.yaml

**3.2 Ejecutar el Pipeline (PipelineRun)**

Crea pipelinerun.yaml. Aquí incluimos el fsGroup: 65532 para evitar errores de permisos en el volumen y usamos el **ServiceAccount** pipeline:

```javascript
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: run-workshop-
spec:
  pipelineRef:
    name: build-and-update-gitops
  serviceAccountName: pipeline
  podTemplate:
    securityContext:
      fsGroup: 65532
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: pipeline-workspace
  params:
    - name: source-repo-url
      value: "https://github.com/<tu-usuario>/app-source.git"
    - name: gitops-repo-url
      value: "https://github.com/<tu-usuario>/app-gitops.git"
    - name: image-tag
      value: "v1.0.0" # Cambia esto en cada ejecución
```

Ejecútalo: oc create \-f pipelinerun.yaml

---

### **Paso 4: Configurar OpenShift GitOps (Argo CD)**

Una vez que el **Pipeline** ha actualizado el repositorio de GitOps, configuramos Argo CD para que escuche esos cambios y los despliegue.

Crea argocd-app.yaml:

```javascript
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workshop-app
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: 'https://github.com/<tu-usuario>/app-gitops.git'
    targetRevision: HEAD
    path: .
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: cicd-tu-nombre
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Aplícalo: oc apply \-f argocd-app.yaml

---

# Automatización

Para exponer un **Listener** (escuchador) que reciba el evento de GitHub cada vez que haces un *push* al código fuente, necesitamos crear tres componentes clave:

1. **TriggerBinding**: Extrae la información del **Payload** JSON que envía GitHub (por ejemplo, la URL del repositorio y el ID del *commit*).  
2. **TriggerTemplate**: Es una plantilla que define cómo crear el **PipelineRun** dinámicamente usando los datos extraídos.  
3. **EventListener**: Es el servicio que se queda escuchando el tráfico HTTP y conecta el *Binding* con el *Template*.

---

### **Paso 1: Crear el TriggerBinding**

Vamos a capturar la URL del repositorio que disparó el evento y el SHA del *commit*. Usaremos el ID del *commit* como nuestro nuevo image-tag, ¡lo cual es una excelente práctica de trazabilidad\!

Crea un archivo llamado github-binding.yaml:

```javascript
apiVersion: triggers.tekton.dev/v1alpha1
kind: TriggerBinding
metadata:
  name: github-push-binding
spec:
  params:
    - name: git-repo-url
      value: $(body.repository.clone_url)
    - name: git-revision
      value: $(body.head_commit.id) # Usaremos el Commit SHA como Image Tag
```

Aplícalo:

```shell
oc apply -f github-binding.yaml
```

### **Paso 2: Crear el TriggerTemplate**

Aquí definimos el **PipelineRun** que se va a generar automáticamente. Notarás que es casi idéntico al pipelinerun.yaml manual que usábamos antes, pero recibe parámetros dinámicos (usando la sintaxis $(tt.params.\*)).

Crea un archivo llamado pipeline-template.yaml *(recuerda reemplazar \<tu-usuario\> en la URL de GitOps)*:

```javascript
apiVersion: triggers.tekton.dev/v1alpha1
kind: TriggerTemplate
metadata:
  name: pipeline-template
spec:
  params:
    - name: git-repo-url
      description: URL del repositorio fuente
    - name: git-revision
      description: El SHA del commit
  resourcetemplates:
    - apiVersion: tekton.dev/v1beta1
      kind: PipelineRun
      metadata:
        generateName: run-workshop-webhook-
      spec:
        pipelineRef:
          name: build-and-update-gitops
        serviceAccountName: pipeline
        workspaces:
          - name: shared-workspace
            persistentVolumeClaim:
              claimName: pipeline-workspace
        params:
          - name: source-repo-url
            value: $(tt.params.git-repo-url) # Viene del Webhook
          - name: gitops-repo-url
            value: "https://github.com/<tu-usuario>/app-gitops.git"
          - name: image-tag
            value: $(tt.params.git-revision) # El tag ahora será dinámico (Commit SHA)
```

Aplícalo:

```shell
oc apply -f pipeline-template.yaml
```

### **Paso 3: Crear el EventListener**

Este componente levanta un **Pod** y un **Service** en tu **Cluster** que escuchará las peticiones HTTP de GitHub.

Crea un archivo llamado github-listener.yaml:

```javascript
apiVersion: triggers.tekton.dev/v1alpha1
kind: EventListener
metadata:
  name: github-listener
spec:
  serviceAccountName: pipeline
  triggers:
    - name: github-push-trigger
      bindings:
        - ref: github-push-binding
      template:
        ref: pipeline-template
```

Aplícalo:

```shell
oc apply -f github-listener.yaml
```

### **Paso 4: Exponer el Listener con un Route**

El **EventListener** crea un **Service** interno llamado el-github-listener. Para que GitHub (que está en internet) pueda alcanzar este servicio, necesitamos exponerlo a través de un **Route**.

Ejecuta este comando en tu terminal:

```shell
oc expose svc el-github-listener
```

Para obtener la URL pública que le daremos a GitHub, ejecuta:

```shell
oc get route el-github-listener --template='http://{{.spec.host}}'
```

*(Copia la URL que te devuelve este comando).*

---

### **Paso 5: Configurar el Webhook en GitHub**

1. Ve a tu repositorio de código fuente (app-source) en GitHub.  
2. Navega a **Settings** \-\> **Webhooks** \-\> **Add webhook**.  
3. En **Payload URL**, pega la URL pública del **Route** que obtuviste en el paso anterior.  
4. En **Content type**, selecciona application/json (¡Muy importante\!).  
5. En la sección *Which events would you like to trigger this webhook?*, deja seleccionado **Just the push event**.  
6. Haz clic en **Add webhook**.

### **¡Prueba la magia de la automatización\!**

Ahora, todo está conectado. Para probarlo:

1. Modifica el archivo index.html dentro de tu Dockerfile en el repositorio app-source (cambia el mensaje a "Hello from Webhook\!").  
2. Haz un git commit y git push.  
3. Ve a tu consola de OpenShift en la sección de **Pipelines** \-\> **PipelineRuns**.

Verás que un nuevo **PipelineRun** se ha lanzado automáticamente. Construirá la nueva imagen usando el *Commit SHA* como **Tag**, actualizará el repositorio de GitOps, y finalmente Argo CD sincronizará el nuevo **Deployment** en tu **Cluster**.

¡Con mucho gusto\! Después de toda la depuración y los ajustes que hicimos juntos, aquí tienes el documento definitivo y actualizado paso a paso.

Este material está listo para que lo uses en tu workshop. Mantiene los términos técnicos en inglés y las explicaciones en español, garantizando que todo funcione a la primera, sin usar la herramienta **CLI** pac.

---

# **Pipeline as Code (otro proyecto)** 

En este workshop aprenderemos a configurar **Pipeline as Code (PAC)** en **OpenShift** desde cero, conectando nuestro cluster con un repositorio de GitHub de forma segura y declarativa.

### **Prerrequisitos**

* Un **Cluster** de **OpenShift** con **OpenShift Pipelines** instalado.  
* Un **Namespace** creado para el workshop (ej. pac-workshop).  
* Un **Repository** en GitHub (ej. https://github.com/tu-usuario/tu-repositorio) con permisos de administrador.  
* Un **Personal Access Token (PAT)** de GitHub con permisos de repo (para que PAC pueda reportar el estado del **Pipeline** en los **Commits** y **Pull Requests**).

---

### **Paso 1: Configurar la Autenticación y Seguridad (Secret)**

Necesitamos almacenar de forma segura dos credenciales en **OpenShift**: el token de la API de GitHub y un token inventado por nosotros para asegurar el **Webhook**.

1. Inventa un token aleatorio para tu Webhook (ej. mi-token-secreto-123).  
2. Genera tu **Personal Access Token** en GitHub (empieza con ghp\_...).  
3. Crea un archivo llamado pac-secret.yaml con el siguiente contenido:

```javascript
apiVersion: v1
kind: Secret
metadata:
  name: webhook-secret
  namespace: pac-workshop
type: Opaque
stringData:
  # 1. El token para autenticar en la API de GitHub (Para Status/PRs)
  github.token: "ghp_AQUI_PONES_TU_TOKEN_DE_GITHUB"
  # 2. El secret para validar que el Webhook realmente viene de GitHub
  webhook.secret: "mi-token-secreto-123"
```

4. Aplícalo en el cluster:

```shell
oc apply -f pac-secret.yaml
```

---

### **Paso 2: Vincular el Repositorio (Custom Resource "Repository")**

Ahora debemos decirle a **OpenShift Pipelines** qué repositorio de Git está autorizado para ejecutar pipelines en este **Namespace** y qué credenciales debe usar.

1. Crea un archivo llamado pac-repository.yaml.  
   *Nota: La url debe ser exactamente igual a la URL de tu repositorio en GitHub.*

```javascript
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata:
  name: mi-repo-pac
  namespace: pac-workshop
spec:
  url: "https://github.com/tu-usuario/tu-repositorio" # Reemplaza con tu URL exacta
  git_provider:
    # Vinculamos el token de la API de GitHub
    secret:
      name: "webhook-secret"
      key: "github.token"
    # Vinculamos el secret de validación del Webhook
    webhook_secret:
      name: "webhook-secret"
      key: "webhook.secret"
```

2. Aplícalo en el cluster:

```shell
oc apply -f pac-repository.yaml
```

---

### **Paso 3: Configurar el Webhook en GitHub**

Ahora debemos configurar GitHub para que envíe un **Payload** a nuestro cluster cada vez que ocurra un evento (como un **Push**).

1. Obtén la **Route** pública del controlador de PAC en tu cluster:

```shell
oc get route pipelines-as-code-controller -n openshift-pipelines
```

2. Ve a tu repositorio en GitHub \-\> **Settings** \-\> **Webhooks** \-\> **Add webhook**.  
3. **Payload URL**: Pega la URL del paso 1 (asegúrate de que empiece con https://).  
4. **Content type**: Selecciona application/json.  
5. **Secret**: Escribe el token inventado del Paso 1 (mi-token-secreto-123).  
6. **Events**: Selecciona **Push** y **Pull Request**.  
7. Guarda el **Webhook**.

---

### **Paso 4: Crear el PipelineRun como Código**

El último paso es crear el archivo que define nuestro pipeline. Este archivo debe vivir directamente en tu código fuente.

1. Clona tu repositorio localmente.  
2. Crea una carpeta llamada .tekton/ en la raíz del proyecto.  
3. Dentro de .tekton/, crea el archivo pipelinerun.yaml.  
4. Pega el siguiente código. Observa cómo usamos las **Annotations** para definir los eventos y para importar la **Task** remota git-clone:

```javascript
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: pac-workshop-run-
  annotations:
    # 1. Eventos que disparan este PipelineRun
    pipelinesascode.tekton.dev/on-event: "[push, pull_request]"
    pipelinesascode.tekton.dev/on-target-branch: "[main]"
    
    # 2. Descargar e inyectar la Task 'git-clone' desde Tekton Hub
    pipelinesascode.tekton.dev/task: "[https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml]"
    
    # 3. Mantener solo las últimas 3 ejecuciones en el historial
    pipelinesascode.tekton.dev/max-keep-runs: "3"
spec:
  pipelineSpec:
    tasks:
      - name: fetch-repository
        taskRef:
          name: git-clone
        params:
          - name: url
            value: "{{ repo_url }}"
          - name: revision
            value: "{{ revision }}"
      
      - name: run-tests
        runAfter:
          - fetch-repository
        taskSpec:
          steps:
            - name: echo-success
              image: alpine
              script: |
                echo "¡El código de la revisión {{ revision }} se descargó con éxito!"
                echo "Pipeline as Code está funcionando a la perfección."
```

5. Haz un **Commit** y un **Push** hacia la rama main en GitHub.

---

### **Paso 5: Validar la Ejecución**

Una vez hecho el **Push**, puedes validar que todo funciona en tres lugares:

1. **En GitHub (Capa de Integración)**:  
   * Ve a los **Commits** de tu repositorio. Deberías ver un ícono verde (✅) indicando que el pipeline pasó, o un círculo amarillo si está en progreso. PAC reporta este estado gracias al token de la API.  
2. **En OpenShift Web Console (Capa de Usuario)**:  
   * Ve a la vista de **Developer**, selecciona el **Namespace** pac-workshop.  
   * Ve a **Pipelines** \-\> **PipelineRuns**. Verás tu pipeline ejecutándose y podrás inspeccionar los **Logs** de cada **Task**.  
3. **En el Controlador de PAC (Capa de Debugging)**:  
   * Si algo falla, revisa los **Logs** del **Pod** pipelines-as-code-controller en el **Namespace** openshift-pipelines.

---

# **Pipeline as Code (mismo proyecto, otra rama)** 

Este apéndice detalla cómo evolucionar nuestra estrategia de CI/CD tradicional hacia **Pipeline as Code**. En este modelo, toda la definición de nuestra integración continua vive en el mismo repositorio que el código fuente (en una nueva **Branch** llamada pac), permitiendo control de versiones y una integración nativa con los **Checks** de GitHub.

Además, esta configuración incluye optimizaciones avanzadas:

1. **Aislamiento de Volúmenes**: Uso de volumeClaimTemplate para crear un **PersistentVolumeClaim (PVC)** efímero por cada ejecución, evitando errores de *Scheduling* (Affinity Assistant) cuando hay ejecuciones concurrentes.  
2. **Namespaces Dinámicos**: Uso de **Context Variables** ($(context.\*.namespace)) para que el **Pipeline** sea completamente agnóstico y reutilizable en cualquier entorno (dev, qa, prod).  
3. **Resolución Automática de Tasks**: PaC descarga automáticamente las **Tasks** oficiales (git-clone, buildah) desde el **ArtifactHub** público de Tekton.

### **Paso 1: Estructura del Repositorio (.tekton)**

En tu repositorio fuente (app-source), crea una nueva **Branch** llamada pac. En la raíz del proyecto, crea un directorio llamado .tekton/. Dentro de esta carpeta, crearemos tres archivos YAML que definen todo nuestro flujo.

#### **1\. La Task Customizada (.tekton/update-gitops-task.yaml)**

Esta **Task** actualiza el **Manifest** y utiliza $(context.taskRun.namespace) para ser dinámica.

```javascript
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: update-gitops-repo
spec:
  workspaces:
    - name: source
  params:
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
  steps:
    - name: git-update
      image: alpine/git:v2.36.2
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -e
        git clone $(params.gitops-repo-url) gitops-repo
        cd gitops-repo
        
        # El namespace se inyecta dinámicamente en tiempo de ejecución
        sed -i "s|image: .*|image: image-registry.openshift-image-registry.svc:5000/$(context.taskRun.namespace)/my-app:$(params.image-tag)|g" deployment.yaml
        
        git config user.email "pipeline@openshift.com"
        git config user.name "OpenShift Pipeline"
        
        git add deployment.yaml
        git commit -m "Update image tag to $(params.image-tag)"
        git push origin main

```

#### **2\. El Pipeline (.tekton/pipeline.yaml)**

Define el orden de las tareas y utiliza $(context.pipelineRun.namespace) para la imagen.

```javascript
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: build-and-update-gitops
spec:
  workspaces:
    - name: shared-workspace
  params:
    - name: source-repo-url
      type: string
    - name: gitops-repo-url
      type: string
    - name: image-tag
      type: string
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.source-repo-url)
          
    - name: build-image
      taskRef:
        name: buildah
      runAfter:
        - fetch-source
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: IMAGE
          # El namespace se inyecta dinámicamente en tiempo de ejecución
          value: image-registry.openshift-image-registry.svc:5000/$(context.pipelineRun.namespace)/my-app:$(params.image-tag)
          
    - name: update-gitops
      taskRef:
        name: update-gitops-repo
      runAfter:
        - build-image
      retries: 1
      workspaces:
        - name: source
          workspace: shared-workspace
      params:
        - name: gitops-repo-url
          value: $(params.gitops-repo-url)
        - name: image-tag
          value: $(params.image-tag)

```

#### **3\. El PipelineRun (.tekton/pipelinerun.yaml)**

Este es el archivo principal que lee **Pipelines as Code**. Configura los **Triggers** mediante **Annotations**, define el volumen dinámico e inyecta las variables de GitHub.

```javascript
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: pac-build-and-update-
  annotations:
    # Eventos que disparan el pipeline
    pipelinesascode.tekton.dev/on-event: "[push]"
    pipelinesascode.tekton.dev/on-target-branch: "[pac]"
    
    # Descarga automática de Tasks oficiales desde ArtifactHub
    pipelinesascode.tekton.dev/task: "[git-clone, buildah]"
spec:
  pipelineRef:
    name: build-and-update-gitops
  serviceAccountName: pipeline
  podTemplate:
    securityContext:
      fsGroup: 65532 
  workspaces:
    - name: shared-workspace
      # Creación dinámica de un PVC efímero para evitar conflictos de Node Affinity
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
  params:
    # Variables dinámicas inyectadas por OpenShift Pipelines as Code
    - name: source-repo-url
      value: "{{repo_url}}" 
    - name: gitops-repo-url
      value: "https://github.com/<tu-usuario>/app-gitops.git" # Reemplazar con tu repo
    - name: image-tag
      value: "{{revision}}" # Se utiliza el Commit SHA como Tag de la imagen
```

*Nota: Haz un git commit y git push de estos tres archivos en tu rama pac.*

### **Paso 2: Registrar el Repositorio en OpenShift**

Para vincular el repositorio con el **Cluster**, crea un **Custom Resource** de tipo Repository en tu **Namespace**.

Ejecuta:

```shell
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: webhook-secret
type: Opaque
stringData:
  # 1. El token para autenticar en la API de GitHub (Status/PRs)
  github.token: "xxxxxx" # Reemplazar
  # 2. El secret para validar que el Webhook viene de GitHub
  webhook.secret: "xxxx" # Reemplazar
---
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata:
  name: bla-source-repo
spec:
  url: "https://github.com/<tu-usuario>/app-source"  # Reemplazar
  git_provider:
    # Vinculamos el token de la API
    secret:
      name: "webhook-secret"
      key: "github.token"
    # Vinculamos el secret del Webhook
    webhook_secret:
      name: "webhook-secret"
      key: "webhook.secret"
EOF
```

### **Paso 3: Configurar el Webhook en GitHub**

1. Obtén la URL pública del controlador global de PaC en OpenShift:

```shell
oc get route pipelines-as-code-controller -n openshift-pipelines --template='https://{{.spec.host}}'
```

2. Ve a la configuración de tu repositorio en GitHub \> **Settings** \> **Webhooks** \> **Add webhook**.  
3. Pega la URL obtenida en **Payload URL**.  
4. Selecciona application/json en **Content type**.  
5. Deja seleccionado **Just the push event** y guarda.

¡Listo\! A partir de este momento, cualquier *push* a la **Branch** pac iniciará el flujo automáticamente, creando volúmenes limpios y reportando el progreso directamente en la interfaz de GitHub.

---

# Referencias:

- [https://github.com/jovemfelix/bla-config](https://github.com/jovemfelix/bla-config)   
- [https://github.com/jovemfelix/bla-source](https://github.com/jovemfelix/bla-source)   
- [https://github.com/jovemfelix/bla-pac](https://github.com/jovemfelix/bla-pac) 

---

### **Manifiesto de Limpieza Automática (Cleanup CronJob)**

Crea un archivo llamado cleanup-cronjob.yaml en tu repositorio de GitOps o aplícalo directamente en tu **Cluster**.

```javascript
# 1. Creamos un ServiceAccount dedicado para la limpieza
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cleanup-sa
  namespace: cicd-tu-nombre # Reemplaza con tu namespace si es diferente
---
# 2. Definimos un Role con los permisos exactos necesarios
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cleanup-role
  namespace: cicd-tu-nombre
rules:
  - apiGroups: ["tekton.dev"]
    resources: ["pipelineruns", "taskruns"]
    verbs: ["get", "list", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "delete"]
---
# 3. Vinculamos el Role al ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cleanup-rolebinding
  namespace: cicd-tu-nombre
subjects:
  - kind: ServiceAccount
    name: cleanup-sa
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cleanup-role
---
# 4. Creamos el CronJob
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tekton-cleanup-job
  namespace: cicd-tu-nombre
spec:
  # Se ejecuta todos los días a la medianoche (formato Cron)
  schedule: "0 0 * * *" 
  successfulJobsHistoryLimit: 3 # Cuántos logs de éxito guardar
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cleanup-sa
          containers:
            - name: tekton-cleanup
              # Usamos la imagen oficial de Tekton CLI
              image: gcr.io/tekton-releases/github.com/tektoncd/cli/cmd/tkn:latest
              command:
                - /bin/sh
                - -c
                - |
                  echo "Iniciando limpieza de PipelineRuns..."
                  # El parámetro --keep 5 retiene los 5 más recientes y borra el resto
                  # El parámetro -f fuerza la eliminación sin pedir confirmación interactiva
                  tkn pipelinerun delete --keep 5 -f
                  echo "¡Limpieza completada con éxito!"
          restartPolicy: OnFailure
```

### **Aplicar el Manifiesto**

Ejecuta el siguiente comando para instalar tu tarea programada:

```
oc apply -f cleanup-cronjob.yaml
```

### **¿Qué logramos con esto?**

* **Ahorro de recursos:** Tu **Cluster** no se quedará sin espacio de almacenamiento debido a decenas de **PVCs** huérfanos.  
* **Limpieza de la Interfaz:** Tu panel de **OpenShift Pipelines** solo mostrará las últimas 5 ejecuciones, manteniéndose rápido y fácil de leer.  
* **Seguridad:** Utilizamos el principio de menor privilegio creando un **ServiceAccount** (cleanup-sa) que solo puede borrar pipelines y volúmenes, nada más.

---

