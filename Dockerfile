FROM rocker/r-ver:4.1.2
RUN apt-get update && apt-get install -y \
    hmmer \
    wget \
    librsvg2-dev \
    sqlite3 libsqlite3-dev\
    && rm -rf /var/lib/apt/lists/*
RUN    R -e "install.packages('BiocManager')"\
    && R -e "BiocManager::install(version = '3.14')" \
    && R -e "BiocManager::install(c('ape','devtools'))" \
    && R -e "install.packages('rsvg')"\ 
    && R -e "install.packages('R.utils')"\ 
    && R -e "BiocManager::install('ChemmineR')" \
    && R -e "devtools::install_github('TylerBackman/bioassayR')" 
ADD . /pubchem-bioassay-database
RUN cd /pubchem-bioassay-database && make working/summarystats.txt
