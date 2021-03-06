# importable variables for reuse
{% set iface_internal = 'enp0s8' %}
{% set iface_external = 'enp0s9' %}
{% set iface_external2 = 'enp0s10' %}


ifassign:
    internal: {{iface_internal}}
    external: {{iface_external}}
    external-alt: {{iface_external2}}


mine_functions:
    internal_ip:
        - mine_function: network.interface_ip
        - {{iface_internal}}
    external_ip:
        - mine_function: network.interface_ip
        - {{iface_external}}
    external_alt_ip:
        - mine_function: network.interface_ip
        - {{iface_external2}}


# You shouldn't use this outside of a LOCAL VAGRANT NETWORK. This configuration
# saves you from setting up a DNS server by replicating it in all nodes' /etc/hosts files.
wellknown_hosts: |
    192.168.56.163   auth.maurusnet.test mail.maurusnet.test calendar.maurusnet.test ci.maurusnet.test
    192.168.56.164   smtp.maurusnet.test

# vim: syntax=yaml
