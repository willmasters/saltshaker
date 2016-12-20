# these states set up and configure the mailsystem CAS server

authserver:
    pkg.installed:
        - name: maurusnet-authserver
        - fromrepo: mn-nightly
        - require:
            - appconfig: authserver-appconfig
    service.running:
        - name: authserver
        - sig: authserver.wsgi
        - enable: True


authserver-appconfig:
    appconfig.present:
        - name: authserver


{% set config = {
    "VAULT_CA": pillar['ssl']['service-rootca-cert'] if pillar['vault'].get('pinned-ca-cert', 'default') == 'default'
        else pillar['vault']['pinned-ca-cert'],
    "BINDIP": pillar.get('authserver', {}).get(
        'bind-ip', grains['ip_interfaces'][pillar['ifassign']['internal']][pillar['ifassign'].get(
            'internal-ip-index', 0
        )|int()]
    ),
    "BINDPORT": pillar.get('authserver', {}).get('bind-port', 8999),
    "DATABASE_NAME": pillar['authserver']['dbname'],
    "DATABASE_PARENTROLE": pillar['authserver']['dbuser'],
    "SPAPI_DBUSERS": ",".join(pillar['authserver']['stored-procedure-api-users']),
    "POSTGRESQL_CA": pillar['ssl']['service-rootca-cert'] if
        pillar['postgresql'].get('pinned-ca-cert', 'default') == 'default'
        else pillar['postgresql']['pinned-ca-cert'],
    "DATABASE_URL": "postgresql://%s:@postgresql.local:5432/%s"|format(pillar['authserver']['dbuser'],
        pillar['authserver']['dbname']),
} %}


{% for envvar, value in config.items() %}
authserver-config-{{loop.index}}:
    file.managed:
        - name: /etc/appconfig/authserver/env/{{envvar}}
        - contents: {{value}}
        - require:
            - file: {{pillar['ssl']['service-rootca-cert']}}
            - appconfig: authserver-appconfig
        - watch_in:
            - service: authserver
{% endfor %}


authserver-tcp-in{{pillar.get('authserver', {}).get('bind-port', 8999)}}-recv:
    iptables.append:
        - table: filter
        - chain: INPUT
        - jump: ACCEPT
        - source: '0/0'
        - destination: {{pillar.get('authserver', {}).get(
            'bind-ip', grains['ip_interfaces'][pillar['ifassign']['internal']][pillar['ifassign'].get(
                'internal-ip-index', 0
            )|int()]
        )}}
        - dport: {{pillar.get('authserver', {}).get('bind-port', 8999)}}
        - match: state
        - connstate: NEW
        - proto: tcp
        - save: True
        - require:
            - sls: iptables

# vim: syntax=yaml
