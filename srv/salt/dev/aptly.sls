
aptly:
    pkgrepo.managed:
        - humanname: Aptly Debian
        - name: {{pillar["repos"]["aptly"]}}
        - file: /etc/apt/sources.list.d/aptly.list
        - key_url: salt://dev/aptly_E083A3782A194991.pgp.key
        - require_in:
            - pkg: aptly
    pkg.installed:
        - name: aptly

# vim: syntax=yaml