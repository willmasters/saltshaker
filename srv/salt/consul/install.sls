#
# Installs Hashicorp Consul in /usr/local/bin from a binary distribution downloaded from the Internet.
# Actual service configuration then happens by assigning the (mutually exclusive) consul.agent or consul.server
# states to a node. The provided consul.service systemd script uses the Saltstack Saltmine to find the servers
# among the salt-master's minions and adds them as cluster nodes.
#
# Bootstrapping the consul cluster is the one area where relying on the salt-master for service discovery makes
# sense. After that, well... you can use consul :).
#
# NOTE:
# This state is included from consul.agent and consul.server so there is basically never a reason where you would
# assign it to a node directly.
#

{% set consul_user = "consul" %}
{% set consul_group = "consul" %}

# We need to make Consul local APIs (DNS and HTTP) available on a routable link-local IP address so
# we can easily use them from separate network spaces like the Docker bridge network.
consul-network-interface:
    file.managed:
        - name: /etc/network/interfaces.d/consul0
        - source: salt://consul/consul0.interface
    cmd.run:
        - name: ifdown consul0; ifup consul0
        - onchanges:
            - file: consul-network-interface


consul-data-dir:
    file.directory:
        - name: /run/consul
        - makedirs: True
        - user: {{consul_user}}
        - group: {{consul_group}}
        - mode: '0755'
        - require:
            - user: consul
            - group: consul


consul-data-dir-systemd:
    file.managed:
        - name: /usr/lib/tmpfiles.d/consul.conf
        - source: salt://consul/consul.tmpfiles.conf
        - template: jinja
        - context:
            user: {{consul_user}}
            group: {{consul_group}}
        - user: root
        - group: root
        - mode: '0644'
        - require:
            - user: consul  # the user is required in the .conf file
            - group: consul


consul-basedir:
    file.directory:
        - name: /etc/consul
        - makedirs: True
        - user: root
        - group: root
        - mode: '0755'


consul-service-dir:
    file.directory:
        - name: /etc/consul/services.d
        - makedirs: True
        - user: {{consul_user}}
        - group: {{consul_group}}
        - mode: '0755'
        - require:
            - user: consul
            - group: consul
            - file: consul-basedir


consul-conf-dir:
    file.directory:
        - name: /etc/consul/conf.d
        - makedirs: True
        - user: {{consul_user}}
        - group: {{consul_group}}
        - mode: '0755'
        - require:
            - user: consul
            - group: consul
            - file: consul-basedir


consul-common-config:
    file.managed:
        - name: /etc/consul/common-config.json
        - source: salt://consul/common-config.jinja.json
        - user: {{consul_user}}
        - group: {{consul_group}}
        - mode: '0600'
        - template: jinja
        - context:
            disable_update_check: >-
                {% if pillar['nomad-cluster'].get('check-for-updates', 'false')|lower == 'true' -%}
                    false
                {%- else -%}
                    true
                {%- endif %}
            local_ip: {{pillar.get('consul-instance', {}).get(
                            'bind-ip', grains['ip_interfaces'][pillar['ifassign']['internal']][pillar['ifassign'].get(
                                'internal-ip-index', 0
                            )|int()]
                        )
                      }}
            consul_interface_ip: 169.254.1.1
            datacenter: {{pillar['consul-cluster']['datacenter']}}
            encryption_key: {{pillar['dynamicsecrets']['consul-encryptionkey']}}
        - require:
            - file: consul-basedir
            - cmd: consul-network-interface


consul:
    group.present:
        - name: {{consul_group}}
    user.present:
        - name: {{consul_user}}
        - gid: {{consul_group}}
        - createhome: False
        - home: /etc/consul/services.d
        - shell: /bin/sh
        - require:
             - group: consul
    archive.extracted:
        - name: /usr/local/bin
        - source: {{pillar["urls"]["consul"]}}
        - source_hash: {{pillar["hashes"]["consul"]}}
        - archive_format: zip
        - unless: test -f /usr/local/bin/consul  # workaround for https://github.com/saltstack/salt/issues/42681
        - if_missing: /usr/local/bin/consul
        - enforce_toplevel: False
    file.managed:
        - name: /usr/local/bin/consul
        - mode: '0755'
        - user: {{consul_user}}
        - group: {{consul_group}}
        - replace: False
        - require:
            - user: consul
            - file: consul-data-dir
            - archive: consul


consul-rsyslog:
    file.managed:
        - name: /etc/rsyslog.d/50-consul.rsyslog.conf
        - source: salt://consul/50-consul.rsyslog.conf
        - user: root
        - group: root
        - mode: '0644'


# open consul interface
consul-all-in-recv:
    iptables.insert:
        - position: 2
        - table: filter
        - chain: INPUT
        - jump: ACCEPT
        - destination: 169.254.1.1
        - save: True
        - require:
            - sls: iptables
            - cmd: consul-network-interface


# redirect ports from localhost
# this requires net.ipv4.conf.all.route_localnet = 1
consul-all-localhost8500-dnat:
    iptables.insert:
        - position: 1
        - table: nat
        - chain: OUTPUT  # not a typo, this is where localhost is routed when localhost is routed in sysctl
        - jump: DNAT
        - to-destination: 169.254.1.1:8500
        - destination: 127.0.0.1/32
        - dport: 8500
        - proto: tcp
        - save: True
        - require:
            - sls: iptables


consul-all-localhost8500-snat:
    iptables.insert:
        - position: 1
        - table: nat
        - chain: POSTROUTING
        - jump: SNAT
        - to-source: 169.254.1.1:8500
        - source: 127.0.0.1/32
        - sport: 8500
        - proto: tcp
        - save: True
        - require:
            - sls: iptables


consul-all-localhost8600-dnat:
    iptables.insert:
        - position: 2
        - table: nat
        - chain: OUTPUT
        - jump: DNAT
        - to-destination: 169.254.1.1:8600
        - destination: 127.0.0.1/32
        - dport: 8600
        - proto: udp
        - save: True
        - require:
            - sls: iptables


consul-all-localhost8600-snat:
    iptables.insert:
        - position: 2
        - table: nat
        - chain: POSTROUTING
        - jump: SNAT
        - to-source: 169.254.1.1:8600
        - source: 127.0.0.1/32
        - sport: 8600
        - proto: udp
        - save: True
        - require:
            - sls: iptables



# open consul ports TCP
{% for port in ['8300', '8301', '8302', '8400', '8500', '8600'] %}
# allow others to talk to us
consul-tcp-in{{port}}-recv:
    iptables.append:
        - table: filter
        - chain: INPUT
        - jump: ACCEPT
        - in-interface: {{pillar['ifassign']['internal']}}
        - dport: {{port}}
        - proto: tcp
        - save: True
        - require:
            - sls: iptables


# allow us to talk to others
consul-tcp-out{{port}}-send:
    iptables.append:
        - table: filter
        - chain: OUTPUT
        - jump: ACCEPT
        - out-interface: {{pillar['ifassign']['internal']}}
        - dport: {{port}}
        - proto: tcp
        - save: True
        - require:
            - sls: iptables
{% endfor %}


# open consul ports UDP
{% for port in ['8301', '8600'] %}
consul-udp-in{{port}}-recv:
    iptables.append:
        - table: filter
        - chain: INPUT
        - jump: ACCEPT
        - in-interface: {{pillar['ifassign']['internal']}}
        - dport: {{port}}
        - proto: udp
        - save: True
        - require:
            - sls: iptables


consul-udp-in{{port}}-send:
    iptables.append:
        - table: filter
        - chain: OUTPUT
        - jump: ACCEPT
        - out-interface: {{pillar['ifassign']['internal']}}
        - sport: {{port}}
        - proto: udp
        - save: True
        - require:
            - sls: iptables
{% endfor %}


# vim: syntax=yaml
