
roledir:
    file.directory:
        - name: /etc/salt/roles.d
        - user: root
        - group: root
        - dir_mode: 700
        - file_mode: 600
        - recurse:
            - user
            - group
            - mode
        - makedirs: True
        - unless: test -h /etc/salt
                  # on vagrant boxes /etc/salt is a symlink on a
                  # vboxsf share and this state can't be ensured

# vim: syntax=yaml

