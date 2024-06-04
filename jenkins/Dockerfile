FROM jenkins/jenkins:2.440.1-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli

COPY add-users.groovy /usr/share/jenkins/ref/init.groovy.d/add-users.groovy

USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow kubernetes matrix-auth json-path-api pipeline-stage-view:2.34"