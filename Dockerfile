# This dockerfile builds a 'live' zap docker image using the latest files in the repos
FROM debian:unstable-slim AS builder

RUN apt-get update && apt-get install -q -y --fix-missing \
	wget \
	curl \
	unzip && \
	apt-get clean

WORKDIR /zap

# Setup Webswing
ENV WEBSWING_VERSION 22.2
ARG WEBSWING_URL=""
RUN if [ -z "$WEBSWING_URL" ] ; \
	then curl -s -L  "https://dev.webswing.org/files/public/webswing-examples-eval-${WEBSWING_VERSION}-distribution.zip" > webswing.zip; \
	else curl -s -L  "$WEBSWING_URL-${WEBSWING_VERSION}-distribution.zip" > webswing.zip; fi && \
	unzip webswing.zip && \
	rm webswing.zip && \
	mv webswing-* webswing && \
	# Remove Webswing bundled examples
	rm -Rf webswing/apps/

FROM debian:unstable-slim
LABEL maintainer="psiinon@gmail.com"

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -q -y --fix-missing \
	make \
	ant \
	automake \
	autoconf \
	gcc g++ \
	openjdk-11-jdk \
	wget \
	curl \
	xmlstarlet \
	unzip \
	git \
	openbox \
	xterm \
	net-tools \
	python3-pip \
	python-is-python3 \
	firefox \
	vim \
	xvfb \
	x11vnc && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*  && \
	useradd -d /home/zap -m -s /bin/bash zap && \
	echo zap:zap | chpasswd && \
	mkdir /zap  && \
	chown zap /zap && \
	chgrp zap /zap && \
	mkdir /zap-src  && \
	chown zap /zap-src && \
	chgrp zap /zap-src

RUN pip3 install --upgrade awscli pip python-owasp-zap-v2.4 pyyaml requests urllib3 

#Change to the zap user so things get done as the right person (apart from copy)
USER zap

RUN mkdir /home/zap/.vnc

ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-amd64/
ENV PATH $JAVA_HOME/bin:/zap/:$PATH

WORKDIR /zap-src

# # Pull the ZAP repo
# RUN git clone --depth 1 https://github.com/zaproxy/zaproxy.git && \
# 	# Build ZAP with weekly add-ons
# 	cd zaproxy && \
# 	ZAP_WEEKLY_ADDONS_NO_TEST=true ./gradlew :zap:prepareDistWeekly && \
# 	cp -R /zap-src/zaproxy/zap/build/distFilesWeekly/* /zap/ && \
# 	rm -rf /zap-src/*

RUN git clone --depth 1 https://github.com/zaproxy/zaproxy.git && \
	git clone --depth 1 https://github.com/zaproxy/zap-extensions.git

RUN cd /zap-extensions && \
	git clone -b dev/fix_start https://github.com/biennd279/next-gen-automation-framework.git ./addOns/next-gen-automation-framework && \
	sed -i '1s/^/include("addOns:next-gen-automation-framework")\n/' settings.gradle.kts && \
	echo 'org.gradle.jvmargs=-Xmx4g' >> gradle.properties && \
	./gradlew copyZapAddon && \
	cd ../

RUN	cd /zaproxy && \
	./gradlew build && \
	cp -R /zap-src/zaproxy/zap/build/distFiles/* /zap/ && \
	rm -rf /zap-src/*

ENV ZAP_PATH /zap/zap.sh
# Default port for use with health check
ENV ZAP_PORT 8080
ENV IS_CONTAINERIZED true
ENV HOME /home/zap/
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

COPY zap* CHANGELOG.md /zap/
COPY --from=builder /zap/webswing /zap/webswing
COPY webswing.config /zap/webswing/
COPY webswing.properties /zap/webswing/
COPY policies /home/zap/.ZAP_D/policies/
COPY policies /root/.ZAP_D/policies/
COPY scripts /home/zap/.ZAP_D/scripts/
COPY .xinitrc /home/zap/

RUN echo "zap2docker-live-naf" > /zap/container

#Copy doesn't respect USER directives so we need to chown and to do that we need to be root
USER root

RUN chown zap:zap /zap/* && \
	chown zap:zap /zap/webswing/webswing.config && \
	chown zap:zap /zap/webswing/webswing.properties && \
	chown zap:zap -R /home/zap/.ZAP_D/ && \
	chown zap:zap /home/zap/.xinitrc && \
	chmod a+x /home/zap/.xinitrc && \
	chmod +x /zap/zap.sh && \
	rm -rf /zap-src

WORKDIR /zap

USER zap
HEALTHCHECK CMD curl --silent --output /dev/null --fail http://localhost:$ZAP_PORT/ || exit 1
