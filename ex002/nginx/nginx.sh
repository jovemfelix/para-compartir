podman build -t alpine-nginx:1.0 -f Dockerfile .
podman run --rm -it --name nginx -p 8080:8080 localhost/alpine-nginx:1.0

curl http://127.0.0.1:8080