FROM docker.io/ubuntu AS release-env

ARG BINARY
ARG TARGETPLATFORM

WORKDIR /app
# copy install file to container
COPY ${TARGETPLATFORM}/agent/* ./

# install rsync
#RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|' /etc/apt/sources.list &&  \
#    apt-get update && apt-get install -y rsync pwgen openssl && \
#    openssl req -x509 -sha256 -new -nodes -days 3650 -newkey rsa:2048 -keyout key.pem -out cert.pem -subj "/C=CN/O=Kosmos/OU=Kosmos/CN=kosmos.io"


RUN sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://mirrors.aliyun.com/ubuntu-ports|g' /etc/apt/sources.list && \
    sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|' /etc/apt/sources.list

RUN apt-get update && \
    apt-get install -y rsync pwgen sudo

COPY ${TARGETPLATFORM}/${BINARY} /app

# install command
CMD ["bash", "/app/install.sh", "/app"]
