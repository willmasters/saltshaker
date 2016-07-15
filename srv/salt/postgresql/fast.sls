
# setting create_main_cluster = false in postgresql-common will prevent the automativ
# creation of a postgres cluster when we install the database
postgresql-step1:
    pkg.installed:
        - name: postgresql-common
    file.managed:
        - name: /etc/postgresql-common/createcluster.conf
        - source: salt://postgresql/createcluster.conf
        - require:
            - pkg: postgresql-step1


data-base-dir:
    file.directory:
        - name: /data/postgres
        - user: postgres
        - group: postgres
        - mode: '0750'
        - require:
            - data-mount


postgresql-step2:
    pkg.installed:
        - pkgs:
            - postgresql
            - postgresql-9.4
            - postgresql-client-9.4
            - libpq5
        - require:
            - postgresql-step1


data-cluster:
    cmd.run:
        - name: /usr/bin/pg_createcluster -d /data/postgres/9.4/main --locale=en_US.utf-8 -e utf-8 9.4 main
        - runas: root
        - unless: test -e /data/postgres/9.4/main
        - require:
            - postgresql-step2
            - data-base-dir
    service.running:
        - name: postgresql@9.4-main
        - sig: postgres
        - enable: True
        - require:
            - cmd: data-cluster


postgresql-in{{pillar.get('postgresql-server', {}).get('bind-port', 5432)}}-recv:
    iptables.append:
        - table: filter
        - chain: INPUT
        - jump: ACCEPT
        - proto: tcp
        - source: '0/0'
        - in-interface: {{pillar['ifassign']['internal']}}
        - destination: {{pillar.get('postgresql-server', {}).get('bind-ip', grains['ip_interfaces'][pillar['ifassign']['internal']][pillar['ifassign'].get('internal-ip-index', 0)|int()])}}
        - dport: {{pillar.get('postgresql-server', {}).get('bind-port', 5432)}}
        - match: state
        - connstate: NEW
        - save: True
        - require:
            - sls: iptables


postgresql-servicdef:
    file.managed:
        - name: /etc/consul/services.d/postgresql.json
        - source: salt://postgresql/consul/postgresql.jinja.json
        - mode: '0644'
        - template: jinja
        - context:
            ip: {{pillar.get('postgresql-server', {}).get('bind-ip', grains['ip_interfaces'][pillar['ifassign']['internal']][pillar['ifassign'].get('internal-ip-index', 0)|int()])}}
            port: {{pillar.get('postgresql-server', {}).get('bind-port', 5432)}}
        - require:
            - service: data-cluster
            - file: consul-service-dir


# vim: syntax=yaml
