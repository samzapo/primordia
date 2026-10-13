# Primordia remote access

The shared GPU world runs continuously on samzapo-desktop; joining does not require starting a local game. Five owner-issued 256-bit personal access keys authorize identities. Give one key to each player. The first sign-in claims an existing living lineage; the same key resumes that identity on another browser instead of granting another body or resources. A browser remembers its opaque session token. Moving an identity to another browser rotates that bearer and disconnects the previous session. New key hashes can be appended later without replacing earlier keys or saved worlds.

The owner keeps plaintext keys privately outside source. Only SHA256 hashes are placed in the repository Actions secret PRIMORDIA_ACCESS_KEY_HASHES and retained target access-keys.json. Neither raw keys nor router credentials enter Git, server logs or Actions output. Keep this registry with world state and the retained TLS authority. Gameplay objective/balance tests remain held; authentication, receipt, transport and recovery checks remain active.

## Current network readiness

Read-only Actions probes confirmed that the target has192.168.1.25, a link-local IPv6 address, no global IPv6 address and noIPv6 default route. A link-local address cannot provide Internet access. The owner identified a Synology RT6600ax at192.168.1.1; SRM HTTPS8001 is reachable and advertises IPv6 and forward-firewall APIs. No authenticated router change has occurred.

## Router credentials and inspection

Add PRIMORDIA_ROUTER_USERNAME and PRIMORDIA_ROUTER_PASSWORD in [this repository’s Actions secrets](https://github.com/samzapo/primordia/settings/secrets/actions). These are the current SRM administrator credentials, separate from the factory Wi-Fi label. Use a dedicated account with the required network permissions when supported. Do not put credentials in workflow inputs, code, command arguments or chat.

The Primordia Synology IPv6 inspection workflow uses a certificate-pinned HTTPS session on the authorized LAN address. The observed certificate SHA256 is c7197b8899f0ce05a0fa163bc3161613688ef27e1f6663e97ae9b2b9939de3f5. A mismatch stops before sending credentials. The initial fingerprint is a LAN-discovery observation, not a publicly certified identity; verify it against the router when establishing trust. Authentication compatibility and any 2FA requirement still need verification. The workflow reads only the IPv6 configuration, narrow firewall defaults and system identity; it does not enable IPv6, create rules, modify Wi-Fi, exposeSRM or change existing services. Responses are reduced to noncredential fields.

## Direct public IPv6 deployment boundary

First verify ISP prefix delegation and router mode support, then establish IPv6 routing/advertisements while preserving IPv4 access. Prepare the game’s IPv6 listener and HTTPS certificate, retain sign-in controls and bounded unauthenticated admission, then allow only the selected game destination/port. Keep unsolicited inbound traffic denied by default and SRM management private. Preserve unrelated firewall rules; retain only the exact settings touched for rollback. Verify actual off-LAN connectivity before reporting a remote URL.

The current LAN CA is constrained to private addresses/localhost and cannot certify a public IPv6 address. [Let’s Encrypt supports public IPv6 IP certificates](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability); they last 160 hours and need automated renewal. [IP address validation](https://letsencrypt.org/docs/challenge-types/) requires HTTP01 on80 or TLSALPN01 on443, so publicly trusted IP TLS may require a separate narrow certificate-validation exception. Do not serve plaintext gameplay on that challenge endpoint. A public IPv6 URL uses brackets, for example https://[the-actual-address]:8766/. No remote endpoint is active yet.

[Synology IPv6 connection guidance](https://kb.synology.com/en-af/SRM/help/SRM/NetworkCenter/internet_connection?version=1_3), [Synology WAN firewall guidance](https://kb.synology.com/en-af/SRM/tutorial/Create_firewall_rules_to_allow_or_deny_IP_addresses_to_access_SRM_or_local_network), and [GitHub Actions secret handling](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) describe the relevant configuration boundaries.
