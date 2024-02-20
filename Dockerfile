FROM openanalytics/r-base

MAINTAINER Tobias Verbeke "tobias.verbeke@openanalytics.eu"

# system libraries of general use
RUN apt-get update && apt-get install -y \
    sudo \
    pandoc \
    pandoc-citeproc \
    libcurl4-gnutls-dev \
    libcairo2-dev \
    libxt-dev \
    libssl-dev \
    libssh2-1-dev \
    libssl1.1 \
    libpq-dev \
    libmariadbclient-dev \
    && rm -rf /var/lib/apt/lists/*

# basic shiny functionality
RUN R -e "install.packages(c('shiny', 'rmarkdown'), repos='https://cloud.r-project.org/')"

# install dependencies of the omim app
RUN R -e "install.packages(c('remotes', 'RSQLite', 'DBI', 'shinyjs', 'shinyBS', 'dplyr', 'DT'), repos='https://cloud.r-project.org/')"
RUN R -e "devtools::install_github(c('rossellhayes/ipa', 'coolbutuseless/phon'))"

# copy the app to the image
WORKDIR /var/data
COPY app /var/data
COPY Rprofile.site /usr/lib/R/etc/

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/var/data')"]
