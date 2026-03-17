podman build -t ubi-hola-httpd:latest -f Dockerfile_RedHat .
podman run --rm -it --name redhat -p 8080:8080 localhost/ubi-hola-httpd:latest

curl http://127.0.0.1:8080