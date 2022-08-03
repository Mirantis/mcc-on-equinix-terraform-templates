FROM alpine:3.13

ENV TERRAFORM_VERSION=0.15.0
ENV ANSIBLE_VERSION=4.6.0
ENV ANSIBLE_LINT_VERSION=5.2.0
# dependencies for ansible
ENV PY_NETADDR_VERSION=0.8.0-r0

ENV HOME_DIR /equinix-infra
ENV ANSIBLE_HOST_KEY_CHECKING=false

COPY . $HOME_DIR
WORKDIR $HOME_DIR

# basic packages
RUN apk --update --no-cache add \
        openssh-client \
        sshpass \
        openssl \
        ca-certificates \
        python3\
        py3-pip \
        py3-cryptography \
        py-netaddr=${PY_NETADDR_VERSION} \
        git \
        bash \
        wget \
        make \
        libc-dev \
        gcc \
        python3-dev

# ansible/tf
RUN pip3 install ansible==${ANSIBLE_VERSION} ansible-lint==${ANSIBLE_LINT_VERSION} && \
	wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
	unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin && \
	rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
