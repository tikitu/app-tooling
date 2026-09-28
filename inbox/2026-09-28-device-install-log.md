# Keep a log of device installs

Left over from the note that became `patterns/git-commit-stamp`
(smooth_saver, 2026-09-27).

**Idea.** Have `make ios-device-run` append each install (time, device,
`AppGitCommit`) to a git-ignored log. It would answer "what was on the phone
last Tuesday", which the stamp alone cannot, but only for installs through
`make`: Xcode's Run button would bypass it, and that is most installs. Worth
doing only if that gap turns out not to matter.
