Bienvenidos a este workshop técnico. Como **Middleware Architect** en Red Hat, mi objetivo hoy es demostrarles por qué **Quarkus** es la elección estratégica para la modernización de aplicaciones Java. Vamos a estructurar esta sesión comparando la agilidad de la **Community** con la estabilidad y el soporte del **Red Hat Build of Quarkus (RHBQ)**.

---

## Phase 1: Environment Setup & Enterprise Repository

Para un entorno de producción o una demo corporativa, no podemos depender únicamente de repositorios públicos. Necesitamos el **Enterprise Repository** de Red Hat para garantizar que los artefactos estén certificados y parcheados.

### **Configuración de Maven (settings.xml)**

Primero, inyectamos el perfil redhat-ga para apuntar a los repositorios oficiales de Red Hat:

```xml
<profile>
  <id>redhat-ga</id>
  <repositories>
    <repository>
      <id>redhat-ga</id>
      <url>https://maven.repository.redhat.com/ga/</url>
    </repository>
  </repositories>
</profile>
```

Aquivo settings.xml completo:

```xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">

  <profiles>
    <profile>
      <id>redhat-ga</id>
      <repositories>
        <repository>
          <id>redhat-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>redhat-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>redhat-ga</activeProfile>
  </activeProfiles>

</settings>
```

herramientas necesarias:

* Openshift Client \- OC

---

## Phase 2: Project Scaffolding (Community vs. RHBQ)

Como arquitectos, debemos entender las diferencias entre el **upstream** (comunidad) y el **downstream** (soporte de Red Hat).

| Component | Community | Red Hat (RHBQ) |
| :---- | :---- | :---- |
| **Maven Plugin** | io.quarkus:quarkus-maven-plugin | io.quarkus.platform:quarkus-maven-plugin |
| **BOM (Bill of Materials)** | io.quarkus.platform | com.redhat.quarkus.platform |
| **Version Strategy** | Bleeding edge (Ex: 3.31.3) | Long Term Support  (Ex: 3.27.2.redhat-00002) |

**Comando para el proyecto Enterprise:**

```shell
# enterprise 01
$ mvn io.quarkus.platform:quarkus-maven-plugin:3.27.0:create \
    -DplatformGroupId=com.redhat.quarkus.platform \
    -DplatformVersion=3.27.2.redhat-00002 \
    -s settings.xml

# enterprise 02
$ mvn io.quarkus.platform:quarkus-maven-plugin:3.27.0:create \
    -DplatformGroupId=com.redhat.quarkus.platform \
    -DplatformArtifactId=quarkus-bom \
    -DplatformVersion=3.27.2.redhat-00002 \
    -DprojectGroupId=org.acme \
    -DprojectArtifactId=meu-projeto-redhat \
    -DclassName="org.acme.GreetingResource" \
    -Dpath="/hello" -s settings.xml

# community
$ mvn io.quarkus.platform:quarkus-maven-plugin:3.31.3:create
```

---

## Phase 3: Developer Joy & Live Coding

El pilar de Quarkus es el **Developer Joy**. Vamos a lanzar la aplicación en **Dev Mode**.

1. **Start:** mvn quarkus:dev \-s ../settings.xml.  
2. **Hot Reload:** Observen cómo al cambiar el GreetingResource, Quarkus realiza un Hot replace en milisegundos (ej: 0.537s).  
3. **Config Injection:** Usamos @ConfigProperty para inyectar valores desde application.properties sin reiniciar el proceso.

```java
package org.acme;

import java.util.Optional;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello")
public class GreetingResource {

    @Inject
    @ConfigProperty(name = "demo.message")
    Optional<String> message;

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello() {
        return message.orElse("hello");
    }
}
```

**Para evaluar:**

```shell
$ http -b :8080/hello

# or

$ curl -s localhost:8080/hello
```

---

## Phase 4: Reactive Middleware Transition

En el mundo del middleware, el bloqueo de threads es el enemigo. La stack moderna de Red Hat utiliza **Mutiny** para un código más legible y performante.

**Identificar dependencias:**

```shell
mvn quarkus:list-extensions
```

**Añadiendo capacidades:**

```shell
mvn quarkus:add-extension -Dextensions="reactive-streams,scheduler"
```

Explicamos el endpoint **Asynchronous**:

* **Uni:** Para un solo resultado.  
* **Multi:** Para flujos de datos.  
* **Scheduler:** Quarkus integra tareas programadas (@Scheduled) de forma nativa sin configurar pools complejos de threads.

```java
package org.acme;

import java.util.Optional;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import io.quarkus.scheduler.Scheduled;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/hello")
public class GreetingResource {

    @Inject
    @ConfigProperty(name = "demo.message")
    Optional<String> message;

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello() {
        return message.orElse("hello");
    }

    @GET
    @Path("/reactive")
    @Produces(MediaType.TEXT_PLAIN)
    public Uni<String> reactive() {
        return Multi.createFrom().items("h", "e", "l", "l", "o")
                .onItem().transform(String::toUpperCase)
                .collect().asList()
                .onItem().transform(list -> list.toString());
    }

    @Scheduled(every = "2s")
    public void tick() {
        System.out.println("Go to sleep!");
    }

}
```

---

## Phase 5: The Native Edge (GraalVM & SubstrateVM)

Aquí es donde Quarkus redefine el **Deployment Density**. Vamos a compilar nuestro código a un binario nativo de Linux usando el profile \-Pnative.

**Build Output Analysis:**

* **Reachable types:** El compilador analiza qué código es realmente necesario, eliminando el resto (AOT \- Ahead of Time).  
* **Image size:** Un binario de aproximadamente 76.16MB que incluye la aplicación y su propia "mini-JVM" (SubstrateVM).

[https://www.graalvm.org/latest/getting-started/linux/](https://www.graalvm.org/latest/getting-started/linux/) 

```shell
$ java -version 
openjdk version "21.0.2" 2024-01-16
OpenJDK Runtime Environment GraalVM CE 21.0.2+13.1 (build 21.0.2+13-jvmci-23.1-b30)
OpenJDK 64-Bit Server VM GraalVM CE 21.0.2+13.1 (build 21.0.2+13-jvmci-23.1-b30, mixed mode, sharing)

$ mvn package -Pnative -DskipTests
```

---

## Phase 6: Performance & Density Metrics

Para terminar, comparamos el **Startup Time** y el **Memory Footprint** contra una stack tradicional.

1\. **Startup & Response Time**

Usamos un loop para detectar el momento exacto en que el puerto 8080 responde :

```shell
# Wait until port 8080 responds
while ! (http --check-status :8080/hello 2>/dev/null); do sleep 0.01; done
```

```shell
$ date +"%T.%3N" && target/code-with-quarkus-1.0.0-SNAPSHOT-runner -XX:+PrintGC -XX:+PrintGCSummary12:27:48.071
....
....
code-with-quarkus stopped in 0.004s
GC summary
  Collected chunk bytes: 0.00M
  Collected object bytes: 0.00M
  Allocated chunk bytes: 27.00M
  Allocated object bytes: 10.20M
  Incremental GC count: 0
  Incremental GC time: 0.000s
  Complete GC count: 0
  Complete GC time: 0.000s
  GC time: 0.000s
  Run time: 0.000s
  GC load: 0%
```

* **Native Startup:** 0.020s.  
* **Time to First Request:** En este workshop, vemos una respuesta total en apenas 84ms desde que presionamos enter.

2\. **Memory Analysis (RSS vs. Virtual)**

El comando ps nos permite extraer una "radiografía" del **Runtime** de nuestro **GraalVM Native Executable**.

```shell
# Encontrar el PID escuchando en el puerto 8080
$ lsof -t -i:8080
176279

$ export QUARKUS_PID=176279
$ ps -p ${QUARKUS_PID} -o %cpu,rss,vsz,min_flt,maj_flt,comm
%CPU   RSS    VSZ  MINFL  MAJFL COMMAND
 0.0 65232 2212364  3748      0 code-with-quark

$ ps -p ${QUARKUS_PID} -o %cpu,rss,vsz,min_flt,maj_flt,comm | numfmt --header --field 2,3 --from-unit=1024 --to=iec-i --suffix=B
%CPU   RSS    VSZ  MINFL  MAJFL COMMAND
 0.0 65MiB  2.2GiB  3901      0 code-with-quark
```

A continuación, el desglose técnico de las métricas obtenidas para este proceso:

### Análisis del Comando y Output de Performance

Para monitorear el **Footprint** y la eficiencia de nuestra aplicación en un entorno **Cloud Native**, analizamos los siguientes indicadores:

| Métrica | Valor en el Log | Explicación Técnica para Arquitectura |
| :---- | :---- | :---- |
| **%CPU** | 0.0 | Indica el uso de ciclos de CPU en el intervalo actual. En reposo, un binario nativo de Quarkus consume recursos mínimos. |
| **RSS** | 65232 (\~65MB) | **Resident Set Size (Real Memory Size)**. Es la memoria física real que el proceso está ocupando en la RAM. Este es el valor crítico para calcular la **Deployment Density** en OpenShift. |
| **VSZ** | 2212364 (\~2GB) | **Virtual Memory Size**. Representa todo el espacio de direccionamiento virtual que el proceso puede acceder, incluyendo bibliotecas mapeadas y el heap reservado. |
| **MINFL** | 3748 | **Minor Page Faults**. Número de veces que el proceso solicitó una página de memoria que ya estaba en RAM pero no asignada a su contexto. Valores bajos tras el startup indican estabilidad. |
| **MAJFL** | 0 | **Major Page Faults**. Indica accesos a disco para recuperar páginas de memoria. Un valor de 0 es ideal, pues significa que no hay latencia de I/O por swap de memoria. |

### Observaciones del Middleware Architect

1. **Memory Footprint**: Observen que el **RSS** es significativamente bajo comparado con una JVM tradicional (que raramente bajaría de 150-200MB para una stack similar con Camel). Esto permite ejecutar múltiples instancias en el mismo nodo.  
2. **Native Efficiency**: El hecho de tener 0 **Major Faults** confirma que el binario nativo ha precargado exitosamente sus estructuras de datos necesarias durante el **Quarkus [Augmentation](https://quarkus.io/guides/reaugmentation)** en tiempo de compilación.  
3. **Process Identification**: Hemos mapeado este análisis directamente al ${QUARKUS\_PID}, lo que permite integrar estos reportes en scripts de telemetría o dashboards de salud del nodo.

**3\. GC Summary**

Gracias a los flags \-XX:+PrintGC \-XX:+PrintGCSummary, vemos que en el binario nativo el **Garbage Collector** es extremadamente eficiente, operando con un heap de apenas 10.20MB para toda nuestra lógica de integración con Camel y JAX-RS.

---

**Summary for the Workshop:** La capacidad de Quarkus para reportar métricas de **Real Memory Size** (RSS) cercanas a los **18MB** y arranques en **sub-100ms** se complementa con estas herramientas de **Troubleshooting**, dándonos un control total sobre el **Runtime** empresarial.

---

## Phase 7: Containerization Strategy & Dockerfile Variants

Cuando listamos el directorio src/main/docker, vemos el resultado del enfoque "opinionated" de Quarkus. No estamos adivinando cómo empaquetar Java; Red Hat ya ha definido las **Best Practices** para cada caso de uso.

```shell
ls -lah src/main/docker
```

### 1\. Dockerfile.jvm (The Modern Standard)

Este es el punto de partida para la mayoría de las migraciones. Utiliza el formato **Fast-jar**.

* **Concepto:** En lugar de un "Fat-jar" gigante, separa las dependencias de la lógica del negocio en capas distintas.  
* **Ventaja:** Optimización extrema de la **Build Cache**. Si solo cambias una línea de código, Docker solo sube una capa de unos pocos KB, manteniendo las dependencias (MBs) intactas en el registro.

### 2\. Dockerfile.legacy-jar (The Compatibility Path)

* **Concepto:** Empaqueta la aplicación como un **Uber-jar** tradicional (un solo archivo .jar con todo adentro).  
* **Ventaja:** Útil para herramientas de despliegue antiguas o integraciones que no soportan estructuras de directorios complejas. Es el "plan B" de la compatibilidad.

### 3\. Dockerfile.native (Production Powerhouse)

Este archivo toma el binario que compilamos y lo coloca sobre una imagen base de Red Hat (**UBI \- Universal Base Image**).

* **Concepto:** El contenedor no contiene una JDK, solo el binario ejecutable y las librerías de sistema mínimas para correr.  
* **Ventaja:** Equilibrio entre **Startup Time** y herramientas de diagnóstico (contiene una shell básica para troubleshooting).

### 4\. Dockerfile.native-micro (The Security Apex)

Esta es la joya de la corona para entornos de **Zero Trust** y alta seguridad.

* **Concepto:** Utiliza **UBI Micro**, una imagen base "distroless" que elimina casi todo lo que no sea estrictamente necesario para ejecutar el binario (sin gestor de paquetes, sin shells innecesarias).  
* **Ventaja:** \* **Attack Surface:** Se reduce drásticamente al eliminar binarios vulnerables del OS.  
  * **Footprint:** El tamaño total de la imagen es minúsculo (muchas veces inferior a 100MB totales).

## ---

### Comparativa Arquitectural para el Workshop

| Dockerfile | Base Image | JVM Required? | Target Use Case |
| ----- | ----- | :---: | ----- |
| **jvm** | UBI Minimal \+ JDK | Yes | Standard Cloud Apps / Debugging easy. |
| **legacy-jar** | UBI Minimal \+ JDK | Yes | Legacy CI/CD Pipelines. |
| **native** | UBI Minimal | No | High Density / Serverless / Knative. |
| **native-micro** | UBI Micro | No | Maximum Security / Hardened Environments. |

## ---

Architect's Insight: Choosing the Right Path

Como arquitectos, nuestra recomendación suele ser:

1. **Desarrollo/QA:** Usar Dockerfile.jvm para mantener la paridad con el **Dev Mode**.  
2. **Producción Estándar:** Dockerfile.native para aprovechar el **Sub-second Startup**.  
3. **Sectores Regulados (Banca/Gobierno):** Dockerfile.native-micro para minimizar los hallazgos en los escaneos de vulnerabilidades de seguridad.

**Final Note:** Observen que el Dockerfile.native-micro tiene solo **861 bytes**. Esto es porque la complejidad se movió al **Build Time**, dejando un **Runtime** limpio y predecible.

###  Multi-stage Dockerfile: El "Full Pipeline" en un solo archivo

En un workshop senior, debemos hablar de **CI/CD Efficiency**. La técnica de **Multi-stage Build** nos permite compilar y empaquetar la aplicación sin necesidad de tener Maven o GraalVM instalados en nuestro agente de Jenkins o GitLab Runner.

¿Cómo funciona el flujo?

1. **Stage 1 (Build):** Usamos una imagen con el JDK y Maven (ej: ubi-minimal) para ejecutar ./mvnw package \-Pnative. Aquí ocurre la **Augmentation** y la compilación nativa.  
2. **Stage 2 (Final):** Tomamos *solo* el binario resultante del Stage 1 y lo movemos a una imagen limpia de ubi-micro.

Ventajas del Multi-stage:

* **Consistency:** El entorno de compilación es idéntico para todos los desarrolladores.  
* **Security:** El contenedor final no contiene herramientas de compilación ni el código fuente, solo el binario ejecutable.  
* **Smaller Artifacts:** Reducimos drásticamente el tamaño de la imagen almacenada en nuestro **Image Registry**.

Ejemplo:

```shell
# ARGUMENTS DEFINITION
ARG QUARKUS_PLATFORM_VERSION=3.27.2.redhat-00002
ARG JAVA_VERSION=21

# STAGE 1: BUIDER (Prepare Maven and Dependencies)
FROM registry.access.redhat.com/quarkus/mandrel-for-java-21-openjdk-rhel9:latest AS builder
USER root
WORKDIR /code

# Copying pom and settings for dependency caching
COPY pom.xml .
COPY settings.xml .
RUN mvn io.quarkus.platform:quarkus-maven-plugin:build -DskipTests -s settings.xml

# STAGE 2: UNIT & INTEGRATION TESTS
FROM builder AS test-stage
COPY src /code/src
RUN mvn test -s settings.xml

# STAGE 3: SONAR ANALYSIS (Static Analysis)
FROM test-stage AS sonar-stage
ARG SONAR_TOKEN
ARG SONAR_HOST_URL=https://sonarcloud.io
RUN mvn sonar:sonar \
    -Dsonar.projectKey=meu-projeto-redhat \
    -Dsonar.host.url=${SONAR_HOST_URL} \
    -Dsonar.login=${SONAR_TOKEN} \
    -s settings.xml

# STAGE 4: NATIVE COMPILATION
FROM sonar-stage AS native-builder
RUN mvn package -Pnative -DskipTests -s settings.xml

# STAGE 5: RUNTIME (The Minimalist Final Image)
FROM registry.access.redhat.com/ubi9/ubi-micro:latest
WORKDIR /work/
# Copying only the native binary from the native-builder stage
COPY --from=native-builder /code/target/*-runner /work/application

# Setting permissions and exposing port
RUN chmod 775 /work
EXPOSE 8080
USER 1001

CMD ["./application", "-Dquarkus.http.host=0.0.0.0"]
```

## ---

## Phase 8: Enterprise Deployment to OpenShift (OCP)

En esta etapa, exploraremos cómo llevar nuestro binario nativo o JVM a producción. OpenShift ofrece una integración profunda con Quarkus que permite automatizar el empaquetado y el despliegue.

**Extensiones Necesarias**

Para habilitar las capacidades de nube y observabilidad, debemos añadir las extensiones correspondientes:

```shell
mvn quarkus:add-extension -Dextensions="openshift,smallrye-health" -s settings.xml
```

* **quarkus-openshift**: Genera automáticamente los manifiestos (DeploymentConfig, Service, Route) y gestiona el build dentro de OCP.  
* **smallrye-health**: Implementa los estándares de MicroProfile Health para monitorear el estado de la aplicación.

## ---

### Método "Native" (Zero-Config Deployment)

Este es el camino del **Developer Joy**. Quarkus utiliza el plugin de Maven para comunicarse directamente con la API de OpenShift.

Propiedades recomendadas (application.properties):

```shell
# Configuración para OpenShift
quarkus.openshift.deploy=true
quarkus.openshift.expose=true
quarkus.openshift.build-strategy=docker
quarkus.native.container-build=true
```

Comando de despliegue:

```shell
mvn clean package -Pnative -Dquarkus.kubernetes.deploy=true -s settings.xml
```

## ---

### Método "Manual" (Control Total / SRE Style)

Como arquitectos, a veces preferimos el control total sobre los manifiestos YAML. Quarkus genera estos archivos en cada build:

1. **Generar manifiestos:** mvn package \-Pnative \-s settings.xml.  
2. **Ubicación:** Los archivos se encuentran en target/kubernetes/openshift.yml.  
3. Aplicación manual:

```shell
oc apply -f target/kubernetes/openshift.yml
```

Este enfoque permite revisar la configuración de recursos (CPU/Memory) antes de impactar el clúster.

## ---

### Observability: Liveness & Readiness Probes

La observabilidad es innegociable en middleware. OpenShift utiliza estas sondas para decidir si reinicia un contenedor (Liveness) o si le envía tráfico (Readiness).

Configuración Customizada:

```shell

# Health Check Customization
quarkus.smallrye-health.root-path=/health
# Liveness: ¿Sigue vivo el proceso (PID)?
quarkus.openshift.liveness-probe.initial-delay=5s
quarkus.openshift.liveness-probe.period=10s
# Readiness: ¿Está Camel listo para procesar rutas?
quarkus.openshift.readiness-probe.initial-delay=2s
```

Al acceder a http://:8080/health, Quarkus reportará el estado de las extensiones instaladas (Camel, Reactive Streams, etc.).

## ---

### Customización de Recursos (Density Tuning)

Recordando nuestro análisis de **RSS** y **Heap**, podemos restringir el contenedor en OpenShift para maximizar la densidad:

```shell
# Límites para un binario nativo (Basado en nuestro análisis de ~18MB RSS)
quarkus.openshift.resources.limits.memory=64Mi
quarkus.openshift.resources.limits.cpu=250m
quarkus.openshift.resources.requests.memory=32Mi
```

Estas restricciones aseguran que nuestra aplicación Quarkus Native utilice solo una fracción de los recursos de un nodo, permitiendo cientos de instancias donde antes solo cabían decenas.

Resumen del Troubleshooting en OCP

Si la aplicación no arranca correctamente, usamos nuestro conocimiento de **PID** y logs:

1. **Ver logs:** oc logs \-f pod/.  
2. **Acceso remoto:** oc rsh pod/.  
3. **Verificar PID internamente:** ps \-ef (si la imagen no es micro).

## References

* CODE: [https://maven.repository.redhat.com/ga/com/redhat/quarkus/platform/quarkus-bom/3.27.2.redhat-00002/](https://maven.repository.redhat.com/ga/com/redhat/quarkus/platform/quarkus-bom/3.27.2.redhat-00002/)  
* Sample: [https://docs.redhat.com/en/documentation/red\_hat\_jboss\_data\_virtualization/6.4/html/installation\_guide/configure\_maven\_to\_use\_the\_online\_repositories](https://docs.redhat.com/en/documentation/red_hat_jboss_data_virtualization/6.4/html/installation_guide/configure_maven_to_use_the_online_repositories)   
* Re-augment: [https://quarkus.io/guides/reaugmentation](https://quarkus.io/guides/reaugmentation) 

---

## Apéndice: Clases de Calidad de Servicio (QoS) en OpenShift

Cuando definimos requests y limits en nuestros manifiestos de Quarkus, OpenShift asigna automáticamente una de estas tres clases para determinar la prioridad del proceso.

### 1\. Guaranteed (Garantizada)

Es el nivel más alto de prioridad. Se asigna cuando los requests son exactamente iguales a los limits (tanto para CPU como para Memoria).

* **Configuración:** requests \== limits.  
* **Ventaja:** El pod tiene asegurado su espacio en el nodo. Es el último en ser eliminado (*evicted*) en caso de falta de recursos.  
* **Uso en Quarkus:** Dado que el **Real Memory Size** (RSS) de un binario nativo es sumamente predecible (ej: \~18MB ), podemos configurar clases **Guaranteed** con límites muy bajos (ej: 32Mi), asegurando una estabilidad absoluta con un costo mínimo.

### 2\. Burstable (Con ráfagas)

Es el nivel intermedio. Se asigna cuando se definen ambos pero el request es menor al limit.

* **Configuración:** requests \< limits.  
* **Ventaja:** Permite que la aplicación consuma más recursos si el nodo los tiene disponibles, pero solo garantiza el mínimo del request.  
* **Uso en Quarkus:** Ideal para aplicaciones que tienen picos de procesamiento (como ráfagas de mensajes en **Camel** o procesos **Scheduled** ), permitiendo que Quarkus use CPU extra temporalmente sin reservar ese costo de forma permanente.

### 3\. Best Effort (Mejor esfuerzo)

Es el nivel más bajo. Se asigna cuando no se define ni requests ni limits.

* **Configuración:** Sin definiciones de recursos.  
* **Ventaja:** No hay reserva de recursos, por lo que el pod puede "flotar" en cualquier nodo con espacio libre.  
* **Riesgo:** Son los primeros en ser eliminados si el nodo se queda sin memoria. No se recomienda para entornos de producción de **Enterprise Middleware**.

---

**Comparativa de Estrategias para Arquitectura**

| Clase QoS | Definición Técnica | Estabilidad | Densidad de Despliegue |
| :---- | :---- | :---- | :---- |
| **Guaranteed** | limits \== requests | Máxima | Alta (con Quarkus Native) |
| **Burstable** | limits \> requests | Media | Muy Alta |
| **BestEffort** | Sin límites | Mínima | Extrema (Riesgosa) |

**¿Por qué Quarkus Native es el "Game Changer" aquí?**

En una JVM tradicional, el **Virtual Memory Size** suele ser masivo (ej: \>4GB ), lo que dificulta asignar clases **Guaranteed** pequeñas. Con Quarkus Native, el **Private Memory Size** es tan reducido (ej: \~9MB ) que podemos desplegar cientos de pods **Guaranteed** en un solo nodo, eliminando el riesgo de *OOM Killer* (Out Of Memory) por parte del kernel.

---

