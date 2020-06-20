#!/usr/bin/env bash

if (( EUID != 0 )); then
    echo "This script must be run as root."
    exit 1
fi

function help {
    echo "USAGE: ${0} <role>"
    echo "Valid roles are: postgres, webapp, elasticsearch, admin, consul."
    exit 1
}

function validate {
    # No argument? That's a paddlin'.
    if [ "x${1}" == "x" ]; then
        help
    fi

    # Invalid function? That's a paddin'.
    VALID_FUNC=`type -t $1 | grep -q function`
    if [ $? != 0 ]; then
        help
    fi
}

function postgres {
    # create DB if it does not exist
    su - postgres -c "psql breakpad -c ''" > log/setupdb.log 2>&1
    if [ $? != 0 ]; then
        echo "Creating new DB, may take a few minutes"
        su postgres -c "PYTHONPATH=. socorro-virtualenv/bin/python \
            application/socorro/external/postgresql/setupdb_app.py --createdb \
            --alembic_config=application/config/alembic.ini --database_name=breakpad \
            --database_superusername=postgres" &> log/setupdb1.log
        if [ $? != 0 ]; then
            echo "WARN could not create database on localhost"
            echo "See /var/log/socorro/setupdb.log for more info"
        fi
    else
        echo "Running database migrations with alembic"
        su postgres -c "PYTHONPATH=. socorro-virtualenv/bin/python \
            socorro-virtualenv/bin/alembic \
            -c application/config/alembic.ini upgrade head" &> log/alembic.log
        if [ $? != 0 ]; then
            echo "WARN could not run alembic migrations"
            echo "See /var/log/socorro/alembic.log for more info"
        fi
    fi
}

function webapp {
    socorro-virtualenv/bin/python \
        webapp-django/manage.py syncdb --noinput \
        &> log/django-syncdb.log
    if [ $? != 0 ]; then
        echo "WARN could not run django syncdb"
        echo "See /var/log/socorro/django-syncdb.log for more info"
    fi
    
    socorro-virtualenv/bin/python \
        webapp-django/manage.py migrate --noinput \
        &> log/django-migrate.log
    if [ $? != 0 ]; then
        echo "WARN could not run django migration"
        echo "See /var/log/socorro/django-migrate.log for more info"
    fi
}

function elasticsearch {
    # create Elasticsearch indexes
    echo "Creating Elasticsearch indexes"
    #pushd /data/socorro/application/scripts > /dev/null
    su socorro -c "PYTHONPATH=. socorro-virtualenv/bin/python \
        application/scripts/setup_supersearch_app.py \
        &> logsetup_supersearch.log"
    
    if [ $? != 0 ]; then
        echo "WARN could not create Elasticsearch indexes"
        echo "See /var/log/socorro/setup_supersearch.log for more info"
        echo "You may want to run"
        echo "/data/socorro/application/scripts/setup_supersearch_app.py manually"
    fi
    #popd > /dev/null
}

function admin {
    # ensure that partitions have been created
    # pushd /data/socorro/application > /dev/null
    su socorro -c "PYTHONPATH=. socorro-virtualenv/bin/python \
        application/socorro/cron/crontabber_app.py --job=weekly-reports-partitions --force \
        &> log/crontabber.log"
    if [ $? != 0 ]; then
        echo "WARN could not run crontabber weekly-reports-partitions"
        echo "See /var/log/socorro/crontabber.log for more info"
    fi
    # popd > /dev/null
}

function consul {
    # load existing config files into Consul
    for conf in *.conf; do
        echo "Bulk loading $conf"
        cat $conf | grep -v '^#' | while read line; do
            key=$(echo $line | cut -d= -f1)
            value=$(echo $line | cut -d= -f2- | tr -d "'")
            prefix="socorro/$(basename -s .conf $conf)"
            result=$(curl -s -X PUT -d "$value" http://localhost:8500/v1/kv/$prefix/$key)
            if [ "$result" != "true" ]; then
                echo "ERROR loading $value into $key for $prefix"
                exit 1
            fi
        done
    done
}

# Aaaaand go!
validate $1
echo "Initialising ${1}."
$1
exit 0
