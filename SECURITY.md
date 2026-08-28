# Security policy

## Supported versions

Security fixes are applied to the current `main` branch. Deployments should track the latest reviewed commit and test it on a representative Windows endpoint before broad rollout.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not include passwords, ConnectWise data, endpoint logs, or other sensitive material in a public issue.

Include the affected script and revision, reproduction conditions, impact, and a minimal redacted proof of concept. You should receive an acknowledgement within seven days.

## Credential and log handling

The `TempAutomateAdmin` password must never be stored in ConnectWise variables, output, transcripts, temporary script source, or child-process command lines. Step 5 keeps the credential in process memory, disables the account in `finally`, and rotates it after use. Step 6 is a defense-in-depth cleanup and should remain the final CWA workflow step.
