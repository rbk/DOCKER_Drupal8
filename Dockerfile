FROM php:7.1-apache

# https://www.drupal.org/node/3060/release
ENV DRUPAL_VERSION 8.3.7
ENV DRUPAL_MD5 e7b1f382d6bd2b18d4b4aca01d335bc0

# Enable Rewrite
RUN a2enmod rewrite

# Dependencies
RUN apt-get update && apt-get install -y mysql-client pv gzip git-core vim wget unzip

# PHP extensions
RUN set -ex \
	&& buildDeps=' \
		libjpeg62-turbo-dev \
		libpng12-dev \
		libpq-dev \
	' \
	&& apt-get update && apt-get install -y --no-install-recommends $buildDeps && rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd \
		--with-jpeg-dir=/usr \
		--with-png-dir=/usr \
	&& docker-php-ext-install -j "$(nproc)" gd mbstring opcache pdo pdo_mysql pdo_pgsql zip \
	&& apt-mark manual \
		libjpeg62-turbo \
		libpq5 \
	&& apt-get purge -y --auto-remove $buildDeps

# Opcache
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=0'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=0'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# php.ini
RUN { \
		echo 'memory_limit = 512M'; \
		echo 'log_errors = On'; \
		echo 'error_log = /var/log/phperror.log'; \
		echo 'error_reporting = E_ALL & ~E_NOTICE'; \
		echo 'max_execution_time = 0'; \
	} > /usr/local/etc/php/php.ini

# Download Drupal 8
WORKDIR /var/www/html
RUN curl -fSL "https://s3.amazonaws.com/core-drupal8-s3/drupal-${DRUPAL_VERSION}.tar.gz" -o drupal.tar.gz \
	&& tar -xz --strip-components=1 -f drupal.tar.gz \
	&& rm drupal.tar.gz \
	&& chown -R www-data:www-data sites modules themes

# Drush USER
RUN /bin/bash -c "useradd drush -m"
RUN /bin/bash -c "usermod -a -G sudo drush"
RUN /bin/bash -c "usermod -a -G www-data drush"

# Composer Setup
USER root
RUN rm -rf vendor
RUN rm composer.lock
RUN chown -R drush:www-data /var/www/html
USER drush
WORKDIR /home/drush

# Install Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php composer-setup.php
RUN php -r "unlink('composer-setup.php');"

# Install Drush
RUN php /home/drush/composer.phar global require drush/drush
ENV PATH="/home/drush/.composer/vendor/bin:${PATH}"
RUN /bin/bash -c 'echo export PATH="/home/drush/.composer/vendor/bin:$PATH" >> /home/drush/.bashrc'

# Install Composer Dependencies
WORKDIR /var/www/html
RUN php /home/drush/composer.phar update

# Copy files
USER root
COPY ./run.sh /root/run.sh
RUN chmod 755 /root/run.sh

# Run
CMD ["/root/run.sh"]
