FROM phusion/baseimage:focal-1.0.0

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

## Set up Android related environment vars

ENV ANDROID_COMPILE_SDK="30"
ENV ANDROID_BUILD_TOOLS="30.0.3"
ENV ANDROID_SDK_TOOLS="6858069"

ARG GRADLE_VERSION=6.8.2
ARG GRADLE_DIST=all
ARG KOTLIN_VERSION=1.5.10

ENV ANDROID_SDK_ROOT="/opt/android-sdk" \
    RUBY_MAJOR=2.6 \
    RUBY_VERSION=2.6.6 \
    RUBY_DOWNLOAD_SHA256=364b143def360bac1b74eb56ed60b1a0dca6439b00157ae11ff77d5cd2e92291 \
    RUBYGEMS_VERSION=3.0.3 \
    FASTLANE_VERSION=2.171.0 \
    YARN_VERSION=1.3.2 \
    NODE_VERSION=9.3.0

WORKDIR /opt

# Install Dependencies
COPY dependencies.txt /var/temp/dependencies.txt
RUN dpkg --add-architecture i386 && apt-get update
RUN apt-get install -y --allow-change-held-packages $(cat /var/temp/dependencies.txt)


# download and install Gradle
# https://services.gradle.org/distributions/
RUN cd /opt && \
    wget -q https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-${GRADLE_DIST}.zip && \
    unzip gradle*.zip && \
    ls -d */ | sed 's/\/*$//g' | xargs -I{} mv {} gradle && \
    rm gradle*.zip


# download and install Kotlin compiler
# https://github.com/JetBrains/kotlin/releases/latest
RUN cd /opt && \
    wget -q https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VERSION}/kotlin-compiler-${KOTLIN_VERSION}.zip && \
    unzip *kotlin*.zip && \
    rm *kotlin*.zip

# Install openjdk-8-jdk 
RUN apt-get update \
    && apt-get install -y openjdk-8-jdk \
    && apt-get autoremove -y \
    && apt-get clean

# Install ruby
RUN mkdir -p /usr/local/etc \
  	&& { \
  		echo 'install: --no-document'; \
  		echo 'update: --no-document'; \
  	} >> /usr/local/etc/gemrc

# some of ruby's build scripts are written in ruby so we purge this later to make sure our final image uses what we just built
RUN set -ex \
    && buildDeps='bison libgdbm-dev ruby' \
    && apt-get update \
    && apt-get install -y --no-install-recommends $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && wget --output-document=ruby.tar.gz --quiet http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-${RUBY_VERSION}.tar.gz \
    && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/ruby \
    && tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1 \
    && rm ruby.tar.gz \
    && cd /usr/src/ruby \
    && { echo '#define ENABLE_PATH_CHECK 0'; echo; cat file.c; } > file.c.new && mv file.c.new file.c \
    && autoconf \
    && ./configure --disable-install-doc \
    && make -j"$(nproc)" \
    && make install \
    && apt-get purge -y --auto-remove $buildDeps \
    && gem update --system $RUBYGEMS_VERSION \
    && rm -r /usr/src/ruby \
    && apt-get autoremove -y \
    && apt-get clean

# install things globally, for great justice and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
  	BUNDLE_BIN="$GEM_HOME/bin" \
  	BUNDLE_SILENCE_ROOT_WARNING=1 \
  	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
	  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

# Install fastlane
RUN gem install fastlane -NV -v "$FASTLANE_VERSION"

# Install command line tools
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip && \
    unzip *tools*linux*.zip -d ${ANDROID_SDK_ROOT}/downloads && \
    mkdir ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    mv ${ANDROID_SDK_ROOT}/downloads/cmdline-tools/* ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm *tools*linux*.zip


# set the environment variables
ENV GRADLE_HOME /opt/gradle
ENV KOTLIN_HOME /opt/kotlinc
ENV PATH ${PATH}:${GRADLE_HOME}/bin:${KOTLIN_HOME}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/cmdline-tools/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator


# WORKAROUND: for issue https://issuetracker.google.com/issues/37137213
ENV LD_LIBRARY_PATH ${ANDROID_SDK_ROOT}/emulator/lib64:${ANDROID_SDK_ROOT}/emulator/lib64/qt/lib


# accept the license agreements of the SDK components
RUN echo yes | sdkmanager --licenses


# Install Android Build Tool and Libraries
RUN sdkmanager --update
RUN yes | sdkmanager "build-tools;${ANDROID_BUILD_TOOLS}" \
    "platforms;android-${ANDROID_COMPILE_SDK}" \
    "tools" \
    "extras;android;m2repository" \
    "extras;google;m2repository" \
    "extras;google;google_play_services"


# Install Build Essentials
RUN apt-get update && apt-get install build-essential -y && apt-get install file -y && apt-get install apt-utils -y

# Cleaning
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
