ARG nginx_version=1.14.0
ARG modsecurity_version=v3.0.3

FROM nginx:${nginx_version} as build

RUN apt-get update \
    && apt-get install -y --no-install-suggests \
       libluajit-5.1-dev libpam0g-dev zlib1g-dev libpcre3-dev \
       libexpat1-dev git curl build-essential libxml2 libxslt1.1 libxslt1-dev autoconf libtool libssl-dev \
    && export NGINX_RAW_VERSION=$(echo $NGINX_VERSION | sed 's/-.*//g') \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_RAW_VERSION.tar.gz -o nginx.tar.gz \
    && tar -zxC /usr/src -f nginx.tar.gz

RUN git clone https://github.com/SpiderLabs/ModSecurity.git && cd ModSecurity && git checkout ${modsecurity_version} \
    && git submodule init && git submodule update && ./build.sh && ./configure && make && make install
RUN strip /usr/local/modsecurity/bin/* /usr/local/modsecurity/lib/*.a /usr/local/modsecurity/lib/*.so*

ARG modules

RUN export NGINX_RAW_VERSION=$(echo $NGINX_VERSION | sed 's/-.*//g') \
    && cd /usr/src/nginx-$NGINX_RAW_VERSION \
    && configure_args=$(nginx -V 2>&1 | grep "configure arguments:" | awk -F 'configure arguments:' '{print $2}'); \
    IFS=','; \
    for module in ${modules}; do \
        module_repo=$(echo $module | sed -E 's@^(((https?|git)://)?[^:]+).*@\1@g'); \
        module_tag=$(echo $module | sed -E 's@^(((https?|git)://)?[^:]+):?([^:/]*)@\4@g'); \
        dirname=$(echo "${module_repo}" | sed -E 's@^.*/|\..*$@@g'); \
        git clone "${module_repo}"; \
        cd ${dirname}; \
        if [ -n "${module_tag}" ]; then git checkout "${module_tag}"; fi; \
        cd ..; \
        configure_args="${configure_args} --add-dynamic-module=./${dirname}"; \
    done; unset IFS \
    && eval ./configure ${configure_args} \
    && make modules \
    && mkdir /modules \
    && cp $(pwd)/objs/*.so /modules

FROM nginx:${nginx_version}

ENV DEBIAN_FRONTEND noninteractive

RUN apt update && \
apt-get install --no-install-recommends --no-install-suggests -y \
ca-certificates \
libcurl4-openssl-dev \
libyajl-dev \
lua5.1-dev \
libxml2

RUN apt clean && rm -rf /var/lib/apt/lists/*

COPY --from=build /modules/* /usr/lib/nginx/modules/
COPY --from=build /usr/local/modsecurity/ /usr/local/modsecurity/
