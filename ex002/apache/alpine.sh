podman build -t alpine-httpd:1.0 -f Dockerfile_Alpine .
podman run --rm -it --name alpine -p 8080:8080 localhost/alpine-httpd:1.0

curl http://127.0.0.1:8080