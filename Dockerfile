FROM python:3.8.10-buster AS build
WORKDIR /

COPY proxy.py . 
COPY lru_cache.py . 
COPY Pipfile Pipfile.lock ./
RUN pip install pipenv
RUN pipenv install --deploy
# COPY safecache safecache
# WORKDIR /safecache 
# RUN pipenv run python setup.py install
WORKDIR /
RUN mkdir /code

EXPOSE 5001
EXPOSE 5010


