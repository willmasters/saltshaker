#
# BASICS: etc_mods is included by basics (which are installed as a baseline everywhere)
# Usually, you won't need to assign this state manually. Assign "basics" instead.
#

inputrc:
    file.managed:
        - name: /etc/inputrc
        - source: salt://etc_mods/inputrc


# Add hostnames for services proxied through the local smartstack-internal HAProxy.
# Some services must have a hostname for SSL to work, so thes aliases can just be added
# to every /etc/hosts
{% set local_aliases = [
    pillar['vault']['smartstack-hostname'],
    pillar['postgresql']['smartstack-hostname'],
    pillar['smtp']['smartstack-hostname'],
]%}
smartstack-hostnames:
    file.append:
        - name: /etc/hosts
        - text: 127.0.0.1    {% for alias in local_aliases %}{{alias}} {% endfor %}


# set up vault command-line client configuration as a convenience in /etc/profile.d
vault-envvar-config:
    file.managed:
        - name: /etc/profile.d/vaultclient.sh
        - contents: |
            export VAULT_ADDR="https://{{pillar['vault']['smartstack-hostname']}}:{{pillar['vault'].get('bind-port', 8200)}}/"
            export VAULT_CACERT="{{pillar['vault']['pinned-ca-cert']}}"
        - user: root
        - group: root
        - mode: '0644'
