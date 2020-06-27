web: sh -c 'cd webapp-django && gunicorn -b 127.0.0.1:8081 --workers=1 --capture-output --reload --log-file=logs/web.log wsgi.socorro-crashstats'
collector: gunicorn --workers=1 --reload --capture-output --log-file=logs/collector.log wsgi.collector
middleware: gunicorn --workers=1 --reload --capture-output --log-file=logs/middleware.log wsgi.middleware
processor: socorro/processor/processor_app.py --admin.conf=config/processor.ini
