FROM centos:8
LABEL maintainer="tdockendorf@osc.edu; johrstrom@osc.edu"

ARG VERSION=latest
ARG CONCURRENCY=4

# setup the ondemand repositories
RUN dnf -y install https://yum.osc.edu/ondemand/latest/ondemand-release-web-latest-1-6.noarch.rpm

# install all the dependencies
RUN dnf -y update && \
    dnf install -y dnf-utils && \
    dnf config-manager --set-enabled powertools && \
    dnf -y module enable nodejs:12 ruby:2.7 && \
    dnf install -y \
        file \
        lsof \
        sudo \
        gcc \
        gcc-c++ \
        git \
        patch \
        lua-posix \
        ondemand-gems \
        ondemand-runtime \
        ondemand-build \
        ondemand-apache \
        ondemand-ruby \
        ondemand-nodejs \
        ondemand-python \
        ondemand-dex \
        ondemand-passenger \
        ondemand-nginx && \
    dnf clean all && rm -rf /var/cache/dnf/*

RUN mkdir -p /opt/ood
RUN mkdir -p /var/www/ood/{apps,public,discover}
RUN mkdir -p /var/www/ood/apps/{sys,dev,usr}

COPY docker/launch-ood      /opt/ood/launch
COPY mod_ood_proxy          /opt/ood/mod_ood_proxy
COPY nginx_stage            /opt/ood/nginx_stage
COPY ood-portal-generator   /opt/ood/ood-portal-generator
COPY ood_auth_map           /opt/ood/ood_auth_map
COPY apps                   /opt/ood/apps
COPY Rakefile               /opt/ood/Rakefile
COPY lib                    /opt/ood/lib

RUN source /opt/rh/ondemand/enable && \
    rake -f /opt/ood/Rakefile -mj$CONCURRENCY build && \
    mv /opt/ood/apps/* /var/www/ood/apps/sys/ && \
    rm -rf /opt/ood/Rakefile /opt/ood/apps /opt/ood/lib

# copy configuration files
RUN mkdir -p /etc/ood/config
RUN cp /opt/ood/nginx_stage/share/nginx_stage_example.yml            /etc/ood/config/nginx_stage.yml
RUN cp /opt/ood/ood-portal-generator/share/ood_portal_example.yml    /etc/ood/config/ood_portal.yml

# make some misc directories & files
RUN mkdir -p /var/lib/ondemand-nginx/config/apps/{sys,dev,usr}
RUN touch /var/lib/ondemand-nginx/config/apps/sys/{dashboard,shell,myjobs}.conf

# setup sudoers for apache
RUN echo -e 'Defaults:apache !requiretty, !authenticate \n\
Defaults:apache env_keep += "NGINX_STAGE_* OOD_*" \n\
apache ALL=(ALL) NOPASSWD: /opt/ood/nginx_stage/sbin/nginx_stage' >/etc/sudoers.d/ood

# sssd for LDAP user database support
RUN dnf install -y sssd

# Install local slurm packages
RUN printf '[c3se-slurm]\nbaseurl = http://hermes-21/repo/centos8/alvis/slurm\nenabled = 1\ngpgcheck = 0\nname = c3se-slurm' >  /etc/yum.repos.d/c3se.repo
RUN dnf install -y slurm

# Install shibboleth and mod_shib
RUN printf '[shibboleth]\ntype=rpm-md\nmirrorlist=https://shibboleth.net/cgi-bin/mirrorlist.cgi/CentOS_8\nenabled = 1\ngpgcheck = 0\nname=Shibboleth (CentOS_8)' >  /etc/yum.repos.d/shibboleth.repo
RUN dnf install -y shibboleth.x86_64

# Clean dnf cache
RUN dnf clean all && rm -rf /var/cache/dnf/*

# run the OOD executables to setup the env
RUN /opt/ood/ood-portal-generator/sbin/update_ood_portal
RUN /opt/ood/nginx_stage/sbin/update_nginx_stage
RUN echo $VERSION > /opt/ood/VERSION
# this one bc centos:8 doesn't generate localhost cert
#RUN /usr/libexec/httpd-ssl-gencerts # we bind mount these

EXPOSE 8080
EXPOSE 5556
EXPOSE 3035
CMD [ "/opt/ood/launch" ]
