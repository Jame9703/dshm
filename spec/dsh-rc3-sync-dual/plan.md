# DSH rc.3 Sync And Dual Release

Target: upstream next 0.2.2-rc.3, local 0.2.2-rc.3+dshm.1. Keep application 1.1.8 / 1010016 unchanged.

1. Preserve existing changes and deliveries; collect registry metadata and byte-hash snapshots. Run the same 113 baseline commands, current CI supplement and 15 targeted checks before changes.
2. Force a real npm installation in the new versioned core work directory. Keep previous lockfile constraints for unaffected dependencies. Preserve pristine search-patch inputs, old work trees and delivery archives.
3. Migrate only proven upstream patch anchors, plugin peers and protocol metadata. Preserve the eleven reviewed fixes and canonical manager update/change lifecycle boundaries, including upstream recovery and install control registration.
4. Repack with --skip-install --place-in-app after installation. Synchronize host resources and OSS; verify source, manifest, installed versions and single resfile archive.
5. Repeat identical checks, then build Beta and AGC sequentially through existing devecocli-backed tools. Guard each build with fresh private original-byte backups and verify exact restoration. Probe devices before AGC replaces Beta caches; do not retry known trust/signature refusal or modify device data.
6. Verify identities, version, devices, permission order/reasons, core and host bytes, OSS, plugin adaptations, signatures/Profile ACLs, sizes and SHA256. Record delivery and limits under dist/acceptance/dsh-rc3-sync-dual. No UI, commits, resets, signing changes, application version changes, permission changes, device routing changes, MEMORY or HANDOFF edits.
