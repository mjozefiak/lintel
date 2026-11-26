# scripts/ax-recon

Recon tool for spec `2026-11-25-meeting-speaker-names`, step 0.2 (gate for F2): does the Accessibility tree of a
meeting window give the participant list and a "speaking now" flag? A developer tool outside the app and outside
the SwiftPM graph. Not part of the build gate or CI.

```sh
scripts/ax-recon/build.sh /tmp/ax          # builds /tmp/ax/ax-recon (needs the terminal to have Accessibility)
ax-recon apps                              # bundle id and pid of running apps
ax-recon webareas <pid>                    # hosts of AXWebArea nodes only (find the Meet tab; no titles, no paths)
ax-recon tree <pid> [--depth N] [--limit N] [--seconds S] [--window-index I] [--show-text]
ax-recon sample <pid> <seconds> [--hz H]   # walk at H Hz: time per walk and the app's CPU
ax-recon manual <pid> get|on|off|enhanced-on|enhanced-off
```

Privacy: by default `tree` prints structure and text lengths only. `--show-text` is only for a test meeting with
fictional names (never for the owner's real browser or real meetings). `webareas` prints hosts only.
Results from the recon are in `docs/meeting-window-ax-recon.md`.
