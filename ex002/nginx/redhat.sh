podman build -t nginx-redhat:1.0 -f Dockerfile_RedHat .
podman run --rm -it --name redhat -p 8080:8080 localhost/nginx-redhat:1.0

curl http://127.0.0.1:8080