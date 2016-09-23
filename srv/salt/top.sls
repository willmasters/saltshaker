#
# maurus.net salt states
#

base:
    '*':
        - basics
        - byobu
        - mn.users
        - roles
        - consul.template  # everything needs consul-template in smartstack
        - haproxy.internal  # everything needs local proxies in smartstack

    # leading "not" is not supported http://docs.saltstack.com/en/latest/topics/targeting/compound.html
    # everything that is not a consul server has a consul agent
    '* and not G@roles:consulserver':
        - match: compound
        - consul.agent

    'roles:consulserver':
        - match: grain
        - consul.server

    'G@roles:secure-database or G@roles:mail':
        - match: compound
        - fstab.secure

    'roles:master':
        - match: grain
        - compilers
        - salt-master

    'roles:vault':
        - match: grain
        - vault

    'roles:dev':
        - match: grain
        - dev.pbuilder
        - dev.aptly
        - dev.fpm
        - dev.concourse.server
        - dev.concourse.worker
#        - dev.pypi
#        - sentry
        - compilers
        - python.dev
        - docker

    'roles:apps':
        - match: grain
        - docker

    'roles:database':
        - match: grain
        - fstab.data
        - fstab.secure
        - postgresql.fast
        - redis.cache
        - dev.concourse.postgres_database
        - postgresql.secure
        - vault.database  # this state is empty if vault doesn't use a database backend
        - vault.postgres_admin  # gives Vault admin rights for using the postgresql Vault secret backend
        - mn.cas.postgres_database # this state is empty if authserver doesn't use a database backend
        - mn.cas.postgres_opensmtpd_access # ^ ditto

    'roles:mail':
        - match: grain
        - dovecot
        - mn.cas.client  # only use with casserver, otherwise comment out
        - opensmtpd.install
        - mail.nixspam
        - mail.spamassassin
        - mail.storage
        - fstab.mailqueue

    'roles:pim':
        - match: grain
        - sogo

    'roles:casserver':
        - match: grain
        - mn.cas.server
        - mn.appconfig

    'roles:loadbalancer':
        - match: grain
        - haproxy.external

    '*.test':
        # put vagrant user config on .test machines
        - mn.users.vagrant
        # enable the NAT networking device for all network traffic
        - iptables.vagrant

# put my personal user on every other machine
    '(?!saltmaster).*?net(|.internal)$':
        - match: pcre
        - mn.users.jonas
