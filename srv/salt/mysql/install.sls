#
# Installs a mysql-multi capable installation of MySQL and registers it with systemd. This does
# not currently support things like replication.
#

mysql-server:
    pkg:
        - installed
        - pkgs:
            - mysql-server
            - python-mysqldb
    service.dead:  # make sure mysql is down before we switch to mysqld-multi
        - name: mysql
        - enable: False
        - prereq:
            - file: mysql-multi
    file.absent:
        - name: /etc/init.d/mysql
        - require:
            - service: mysql-server


mysql-config:
    file.managed:
        - name: /etc/mysql/my.cnf
        - source: salt://mysql/my.cnf
        - user: mysql
        - group: mysql
        - require:
            - pkg: mysql-server


# change config folder ownership to mysql:mysql because that's what we use in mysql@.service
mysql-config-folder:
    file.directory:
        - name: /etc/mysql
        - user: mysql
        - group: mysql
        - require:
            - service: mysql-server


mysql-data-dir:
    file.directory:
        - name: /run/mysqld
        - makedirs: True
        - user: mysql
        - grouup: mysql
        - mode: '0755'
        - require:
            - pkg: mysql-server


mysql-data-dir-systemd:
    file.managed:
        - name: /usr/lib/tmpfiles.d/mysqld.conf
        - source: salt://mysql/mysqld.tmpfiles.conf
        - user: root
        - group: root
        - mode: '0644'
        - require:
            - pkg: mysql-server


mysql-multi:
    file.managed:
         - name: /etc/systemd/system/mysql@.service
         - source: salt://mysql/mysql@.service
         - user: root
         - group: root
         - mode: '0644'
         - require:
             - pkg: mysql-server
             - file: mysql-multi-config
             - file: mysql-multi-includedir-patch


mysql-multi-config:
    file.directory:
        - name: /etc/mysql/conf.d
        - makedirs: True
        - user: mysql
        - group: mysql
        - dir_mode: '0750'
        - mode: '0640'
        - recurse:
            - user
            - group
            - mode


# work around http://bugs.mysql.com/bug.php?id=29327
mysql-multi-includedir-patch:
    file.patch:
        - name: /usr/bin/mysqld_multi
        - source: salt://mysql/mysqld_multi.patch
        - hash: md5=b9ae0de4f3235fbe03de12a6dfbcafa8


/etc/mysql/debian.cnf:
    file:
        - managed
        - source: salt://mysql/debian.jinja.cnf
        - template: jinja
        - context:
            prefix: ''
            ip: localhost    # debian-sys-maint is always local
            port: 3306
            password: {{pillar['dynamicpasswords']['debian-sys-maint']}}
        - mode: 600
        - user: root
        - group: root
        - require:
            - pkg: mysql-server


# vim: syntax=yaml
