# cloudflare-cli
CLI to Edit Cloudflare DNS Records

This command line tool to update Cloudfare DNS records is useful in the following scenarios:

* Keeping dynamic DNS records up to date
* Updating DNS records as part of the ACME DNS-01 protocol

The tool has the following dependencies:

* Posix shell (Busybox ash, Bash, etc)
* grep(1)
* curl(1)
* [JSON.sh](https://github.com/dominictarr/JSON.sh)

The limited set of dependencies makes this implementation easy to deploy, and makes it suited for embedded environments such as OpenWRT. The focus of this implementation wide applicability and ease of deployment, rather than performance.

# Deployment

* Place cloudflare-cli, cloudflare-cli.sh and json.sh in a common directory of your choice

# Usage

Prerequisites:

* The email address associated with the Cloudflare account
* The API token associated with the Cloudflare account

## Query an Existing Record

* `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com A @`
 * Query the DNS A record of domain.com.
*  `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com CNAME www`
 * Query the DNS A record of www\.domain\.com.
* `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com TXT _acme-challenge.www`
 * Query the DNS TXT record of _acme-challenge\.www\.domain\.com

## Create or Modify an Existing Record

* `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com A @ = 10.12.34.21`
 * Modify the DNS A record of domain.com setting it to 10.12.34.21
* `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com TXT _acme-challenge.www = 12345`
 * Modify or create the DNS TXT record of _acme-challenge\.www\.domain\.com

## Delete

* `cloudflare-cli name@mail.com 1234abcd1234abcd1234abcd1234f domain.com TXT _acme-challenge.www =`
 * Delete the DNS TXT record of _acme-challenge\.www\.domain\.com
