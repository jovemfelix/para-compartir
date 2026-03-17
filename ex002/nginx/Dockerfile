# Usar la base image del Nginx con Alpine
FROM docker.io/library/nginx:alpine

# 1. Remover la directiva 'user' (causa error en OpenShift si no es root)
RUN sed -i '/user  nginx;/d' /etc/nginx/nginx.conf

# [OPCIONAL] Limitar a 1 solo worker process para simplificar logs en testing
RUN sed -i 's/^worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf

# 2. Solución agresiva para el PID: 
# Borramos cualquier configuración de 'pid' existente e inyectamos la nuestra en la línea 1 apuntando a /tmp
RUN sed -i '/^pid/d' /etc/nginx/nginx.conf && \
    sed -i '1i pid /tmp/nginx.pid;' /etc/nginx/nginx.conf

# 3. Cambiar el port de escucha predeterminado de 80 a 8080
RUN sed -i 's/listen  *80;/listen 8080;/g' /etc/nginx/conf.d/default.conf

# 4. Crear el archivo index.html con el texto "hola"
RUN echo "prueba" > /usr/share/nginx/html/index.html

# 5. Ajustar permisos para compatibilidad con OpenShift (GID 0)
# Incluimos /run en los permisos por si los scripts de inicialización (entrypoint) lo necesitan
RUN chgrp -R 0 /var/cache/nginx /var/log/nginx /usr/share/nginx/html /etc/nginx /run /tmp && \
    chmod -R g=u /var/cache/nginx /var/log/nginx /usr/share/nginx/html /etc/nginx /run /tmp

# Exponer el port 8080
EXPOSE 8080

# Definir un non-root user para ejecución
USER 1001