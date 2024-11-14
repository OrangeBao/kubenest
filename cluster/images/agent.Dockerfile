FROM m.daocloud.io/docker.io/ubuntu AS release-env

ARG BINARY

WORKDIR /app
# copy install file to container
# build context is _output/xx/xx
COPY agent/* ./

# install rsync
#RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|' /etc/apt/sources.list &&  \
#    apt-get update && apt-get install -y rsync pwgen openssl && \
#    openssl req -x509 -sha256 -new -nodes -days 3650 -newkey rsa:2048 -keyout key.pem -out cert.pem -subj "/C=CN/O=Kosmos/OU=Kosmos/CN=kosmos.io"


RUN sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://mirrors.aliyun.com/ubuntu-ports|g' /etc/apt/sources.list && \
    sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|' /etc/apt/sources.list

RUN apt-get update && \
    apt-get install -y rsync pwgen

COPY ${BINARY} /app

# install command
CMD ["bash", "/app/install.sh", "/app"]
