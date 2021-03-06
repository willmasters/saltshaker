Certifying builds
=================

> All of the ideas presented in this document are supported by the
> `vaultgetcert` tool that is part of
> [GoPythonGo](https://github.com/gopythongo/gopythongo).

There are four common pitfalls of secret management in modern automated server
configuration:

  1. Your secret configuration (like database credentials) is in your shared
     source code repository ("everyone on the dev team has it")

  2. Your secret configuration is in your shared configuration management
     repository ("everyone on the ops team has it")

  3. Even if you use a deployment specific secrets database like the
     `dynamicsecrets` pillar included in this repository, you commonly must
     run the configuration management before deploying new applications so
     their secrets are waiting for them.

  4. Worst case scenario: hard-coded credentials are duplicated in your source
     code and your configuration and reused between different deployment
     environments so you don't have to do code changes before deploying.

Generally speaking this also interferes with Continuous Delivery and also makes
it really hard to rotate passwords and other secrets when people leave your
company or you detected an attack. Many security standards and best practices
like PCIDSS also require secrets to be rotated regularly.

So the build model ingrained into this repository is based on
[Hashicorp Vault](https://vaultproject.io/) and moving secret generation where
it belongs: on the build server. Vault's "PKI" secret management backend
creates a world where managing your own organization's certificate authorities
is cheap and easily automated. This allows us to think about infrastructure
where each service is authenticating clients through its own CA, even having
per-environment CAs is easy to implement. This enables secret generation on the
build server at scale and gives us interesting properties, like for example,
easy tracking of secret propagation (what build server created the certificates
used by a build at what exact time and what was the git commit hash the build
was based on). By using Vault for credential management inside deployment
environments we can then solve additional issues, like ensuring fine-grained
audit logs.

Moving secret management to the build server in a continuous delivery
environment makes sense, because:

  1. You must trust and secure your build server anyway. If it's compromised the
     attacker can deploy malicious code and can also read all of your hardcoded
     secrets.

  2. You can lock the build server down for your developers and ops people, but
     you can't deny them access to source code and configuration management, so
     this limits secret exposure throughout your organization.

  3. If you follow [12factor](https://12factor.net), as much configuration as
     possible should be part of your release artifacts, since a release is
     always code **plus** configuration. Most of the build and deployment ideas
     in this repository are based on that concept.

That said, this is what we do to reach that goal:

  1. have a build server that builds your applications for CI and CD.

  2. that build server has a (network)-local Vault instance.

  3. that Vault instance can issue certificates from a local "application CA"
     or "deployment environment CA" using the `PKI` secret backend.

  4. The build scripts (using GoPythonGo, for example) request a new
     certificate for each build and put them in the delivery artifact (i.e.
     Docker container or .deb/.rpm) together with environment variable sources
     (i.e. a file in /etc/defaults loaded by systemd through
     `EnvironmentFile=`) pointing to the file. The certificate has the app name
     in the `CN` attribute or is issued by an application-specific CA.

  5. Each app uses its build certificate issued by the build server to access
     internal services like a local PostgreSQL database (`cert`
     authentication), Vault instance, etc.

This way, **every** build gets it's own pair of credentials, is packaged up and
sent off to be installed on your servers. Vault's PKI backend stores the CA key
and has no way of exporting it short of reading its allocated RAM. The keys to
unseal the build server Vault can be easily distributed using Vault's built-in
key management protocols. Finally, a distributed Vault storage backend like
Amazon S3 makes it easy to deploy new build servers and only few people on your
Ops team need to have access to the build server and/or the CAs used to certify
the automated build server PKIs. Using internal policies, split passphrases
and an airgapped box, Yubikey or full-blown HSM you can ensure that no new
build CAs can be certified without your knowledge.

Your configuration management only knows about the public CA certificates.
Basically this works, because Vault makes running automated intermediate CAs
easy and cheap.

Using Vault for resource management
-----------------------------------
If multiple environments are being serviced, they can share an application
root CA with one Vault-managed intermediate CA per environment. Then,
applications built for one environment can also be used in a different
environment, which might be desirable if deployment artifacts are being
"promoted" between environments.  Since Vault is currently
binding policies *to CA certificates*, the application must be at the root
of the CA tree to allow for separating applications access to Vault
resources.

In any case it is good practice to also add intermediaries *for each build
server*, so certificates can be easily revoked if a server gets
compromised or just removed. It also automatically leaves an audit trail
for which server the build was built on.

```
                   +-------------+  manually managed
                   | myapp       |  CA pathlen: 2
                   +-------------+
                   /      |       \
          +---------+ +-------+ +---------+  manually managed
          |  Stage  | |  Dev  | |   Live  |  intermediaries pathlen: 1
          +---------+ +-------+ +---------+
          /     |       |   |       |     \
      +----+ +----+ +----+ +----+ +----+ +----+  Vault managed build server
      | B1 | | B2 | | B1 | | B2 | | B1 | | B2 |  intermediary. pathlen: 0
      +----+ +----+ +----+ +----+ +----+ +----+
```

Alternatively, each environment could get its own application root CA,
ensuring that each build has unique credentials for its target
environment meaning that builds can't be moved between environments.

```
     +-----------+ +-------------+ +------------+  manually managed CAs
     | myapp Dev | | myapp Stage | | myapp Live |  pathlen: 1
     +-----------+ +-------------+ +------------+
       |       |      |       |      |       |
     +----+ +----+  +----+ +----+  +----+ +----+  Vault managed build
     | B1 | | B2 |  | B1 | | B2 |  | B1 | | B2 |  server intermediaries.
     +----+ +----+  +----+ +----+  +----+ +----+  pathlen: 0
```

If you're willing to rotate intermediaries and transport private keys
between the Vault instances or share a Vault instance between all build
servers, you can cut down the number of CAs to 7 or 6 respectively and
when Vault implements
[#1823](https://github.com/hashicorp/vault/issues/1823), you can cut down
the number of needed CAs even further.

Using SSL client authentication with individual resources
---------------------------------------------------------
The above works well if you use Vault inside your environments *and* on the
build server, so that it also issues limited database credentials to your
application, because as mentioned, Vault assigns policies to *the issuing CA*.

However, if you want to use the build-issued certificates to authenticate to
services directly, for example OpenSMTPD and PostgreSQL, you will run into the
problem that each of these services can only trust a single client certificate
authority at a time. So unless you have only a single application,
you have two options:

  1. **Don't use Vault and restructure the CA tree by putting the environment at
     the root(s).**

     ```
             +--------+ +--------+ +--------+  manually managed CAs
             | Dev    | | Stage  | | Live   |  pathlen: 1
             +--------+ +--------+ +--------+
            /     |       |     |      |     \
       +----+ +----+  +----+ +----+  +----+ +----+  Vault managed build
       | B1 | | B2 |  | B1 | | B2 |  | B1 | | B2 |  server intermediaries.
       +----+ +----+  +----+ +----+  +----+ +----+  pathlen: 0

     ```

     PostgreSQL and most other services differentiate permissions through the
     certificate's CN attribute, so in this case in each environment PostgreSQL
     would be configured to trust the environment CA using `ssl_ca_file`, which
     can only take a single value.

  2. **Use multiple trust paths.**

     What this means is that you create one
     environment CA and one application CA. You configure Vault to trust the
     application CA and non-Vault-managed services to trust the environment
     CA. Then you create the **one** intermediary CA, which one doesn't matter.
     **Then you cross-sign the intermediary from the other root CA**. This will
     give you multiple valid certificate chains. You then create **one**
     certificate for each build with **two** valid certificate chains, each
     leading to a different root: *one using the application CA intermediary
     certificate which was signed by the application root CA* and *one using
     the application CA intermediary certificate signed by the environment CA*.
     You ship both chains with your application and configure/program the
     application to present the correct certificate chain when interacting with
     Vault or another service. Note: The intermediary certificates each use
     the same public/private key pair.

     In this case PostgreSQL would be configured to trust the environment root
     CA, allowing it to service multiple different applications and Vault would
     be configured to trust the application root CA allowing it to bind
     policies to the CA.

     ```
          +---------+  +-----------+  manually managed root CAs
          |  Stage  |  | myapp Dev |  pathlen: 1
          +---------+  +-----------+
                |          |
         +----------------------------+
         |  Cross-signed build server |  Vault managed build server
         |  (2 certificates for one   |  intermediary. pathlen: 0
         |  intermediary CA keypair)  |
         +----------------------------+
     ```

     Unfortunately this requires a bit more logic on the application's side as
     it has to present the correct certificate chain when it talks to a
     service. In GoPythonGo's toolchain, `vaultgetcert` supports this through
     its `--xsign-cacert` and `--output-bundle-envvar` parameters, which create
     12factor environment variable settings in [appconfig](ETC_APPCONFIG.md)
     format to make selecting the right trust-path easy.

Why not make this a tidy tree and put a organization root CA at the top?
------------------------------------------------------------------------
Because OpenSSL and by extension most software using `libssl`, will follow the
trust path of a SSL client certificate to the "logical end of the trust chain",
*a self-signed CA*. This means that you usually **can't terminate a trust chain
at an intermediary CA**. In other words: Your services would trust every
certificate signed by **any intermediary** under your root CA, not just the PKI
branch represented.

Local development
-----------------
Local development is easy since developers can just use a local
environment that uses username/password auth instead by setting the
required environment variables.

Since the dev/stage/production environments rely on Smartstack, all
applications expect to find their required services on localhost anyway.

For extra security or at least a better audit trail, the live system could
require applications to use their "appcert" to request credentials for their
database through their local Vault instance, thereby leaving an audit trail for
the database credentials.

Using cross-signed client certificates with different software
--------------------------------------------------------------

### Python requests
You pass the correct bundle into the `cert=` keyword parameter. The file
contains:

  1. The client certificate issued by the build server intermediary
  2. The application CA or environment CA cross-signature

```python
requests.get(url, cert=('cert_plus_intermediate_from_correct_root.pem', 'key.pem'))
```

### OpenSSL
To test this setup you'll want to run `openssl s_server` and `openssl s_client`
against each other:

```
# run a local TLS1.2 server on port 8443
openssl s_server \
    -cert server_cert.pem \
    -key server_key.pem
    -tls1_2
    -Verify 3
    -verify_return_error
    -CAfile application_or_environment_root+server_intermediary(if_needed).pem
    -accept 8443

# connect to this server, if this works client *and* server have verified
# correctly
openssl s_client \
    -cert client_cert.pem \
    -key client_key.pem \
    -CAfile application_or_environment_intermediary(x-signed)+server_root.pem \
    -tls1_2 \
    -showcerts \
    -verify 3 \
    -verify_return_error \
    -connect localhost:8443
```

`server_cert.pem` and `server_key.pem` haven't been mentioned in this document,
they are simply normal server-side SSL certificates. If you don't have any, you
must create one.

`application_or_environment_root+server_intermediary(if_needed).pem` is a
concatenated text file containing whichever of your two client root CAs you
want to use and if your server certificate was signed (as is commonly the
case) by an intermediary CA itself, you must also include that certificate
so the *client* can build a trust chain to the server certificate's CA.

`application_or_environment_intermediary(x-signed)+server_root.pem` is a
concatenated text file containing the cross-signature intermediary
certificate that is right for the client root CA you chose for the server.
Since OpenSSL *does not read the system certificate store*, you also **must**
include the root CA for `server_cert.pem`, so your client can validate the
server's certificate before presenting its client certificate.

`client_cert.pem` and `client_key.pem` are the client certificate and its
private key as issued by the cross-signed intermediary CA managed by Vault
(see the Vault cheatsheet below on how to issue a client certificate using the
PKI secret backend).

#### What about -CApath
Instead of creating concatenated files, you could also use a folder containing
all of the necessary certificates in individual files using the `-CApath`
command-line parameter. However, that folder **must be in hashdir format**.
See the OpenSSL verify manpage to find out what that is. If you don't provide
it like that, OpenSSL will just silently fail certificate validation!


Command cheatsheet
------------------
```
# Create a "Myapp Dev" CA using openssl or other appropriate software.
# That CA will be installed in the environment's Vault.

# Mount one PKI backend per environment that gets its own builds on this server
# and allow builds to remain valid for 1 year (tune to your specifications)
vault mount -path=pki-myapp-dev -default-lease-ttl=8760h \
    -max-lease-ttl=8760h pki

# Generate an intermediate CA with a 2048 bit key (default)
vault write pki-myapp-dev/intermediate/generate/internal \
    common_name="Myapp Dev Automated Build Server CA X1"

# Sign the intermediate CA using your private Myapp Dev CA
# then write the certificate back to the Vault store
vault write pki-myapp-dev/intermediate/set-signed certificate=-

# Cross sign the certificate with your environment CA if you
# want to follow the split model described above!

# You can also use the root certificate with a trustchain
# in the client certificate.
vault write pki-myapp-dev/roles/build ttl=8760h allow_localhost=false \
    allow_ip_sans=false server_flag=false client_flag=true \
    allow_any_name=true key_type=rsa

# Request a build certificate for a build
# We "hack" the git hash into a domain name SAN because Vault currently
# doesn't support freetext SANs. This should run in your build scripts.
vault write pki-myapp-dev/issue/build common_name="vaultadmin" \
    alt_names="024572834273498734.git" exclude_cn_from_sans=true
```
