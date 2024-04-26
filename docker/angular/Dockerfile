# node base image
FROM registry.access.redhat.com/ubi8/nodejs-16:1-52 as builder

USER 1001

# copy dependency list to take advantage of cached layers
COPY --chown=1001:0 package*.json ./

# run npm install
RUN npm install

# copy everything to current working directory
COPY src ./src
COPY angular.json tsconfig.app.json tsconfig.json tsconfig.spec.json ./

# run the build
RUN npm run build

# nginx base image
FROM registry.access.redhat.com/ubi8/nginx-120

# copy nginx config file
COPY --chown="1001:0" ./docker/config/nginx.conf ${NGINX_CONF_PATH}

# copy entrypoint
COPY --chown="1001:0" ./docker/config/docker-entrypoint.sh ${NGINX_APP_ROOT}

# copy static files compiled with npm
COPY --chown="1001:0" --from=builder /opt/app-root/src/dist/secad-app ${HOME}

ENV ENVIRONMENT_CFG=${HOME}/assets/config/environment.json \
    ENVIRONMENT_CFG_TPL=${HOME}/assets/config/environment.tpl.json \
    ENVIRONMENT_CFG_TMP=/tmp/environment.tmp.json

# copy additional files like templates
COPY --chown="1001:0" ./docker/config/environment.tpl.json ${ENVIRONMENT_CFG_TPL}
COPY --chown="1001:0" ./docker/config/environment.tpl.json ${ENVIRONMENT_CFG}

# add user permissions
RUN chmod a+rwx ${NGINX_CONF_PATH} && \ 
    chmod ug+rx ${NGINX_APP_ROOT}/docker-entrypoint.sh && \
    chmod -R ug+r ${HOME} && \  
    chown -R 1001:0 ${HOME} && \  
    chmod ug+rw ${ENVIRONMENT_CFG}

# run entrypoint
ENTRYPOINT ["/opt/app-root/docker-entrypoint.sh"]
