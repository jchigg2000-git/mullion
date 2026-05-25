# Contributing to Mullion

Thanks for your interest in contributing. This is a small project and
contributions of any size are welcome — bug reports, fixes, new layouts,
documentation, or design feedback.

## Developer Certificate of Origin (DCO)

Mullion uses the [Developer Certificate of Origin](https://developercertificate.org/)
instead of a Contributor License Agreement. The DCO is a lightweight
statement that you wrote the code you're submitting (or otherwise have the
right to submit it under the project's MIT license). There's no form to
sign and no account to create — you certify the DCO per commit by adding
a `Signed-off-by` line.

### How to sign off

Use the `-s` flag when you commit:

```sh
git commit -s -m "your commit message"
```

That automatically appends a line like:

```
Signed-off-by: Jane Developer <jane@example.com>
```

using the name and email from your `git config`. Make sure those are set
to something real:

```sh
git config user.name  "Your Name"
git config user.email "you@example.com"
```

If you forget to sign off on a commit, amend it:

```sh
git commit --amend -s --no-edit
```

For a branch with multiple unsigned commits, rebase:

```sh
git rebase --signoff main
```

Pull requests with unsigned commits will be asked to sign off before merge.
The full DCO text is at the bottom of this file for reference.

## Development setup

- macOS 13+ recommended (the Accessibility API surface is most consistent
  on recent macOS).
- Xcode 15+.
- Clone, open `Mullion.xcodeproj`, build and run.
- First launch will prompt for Accessibility permission. Grant it in
  System Settings → Privacy & Security → Accessibility.

## Filing issues

For bugs, please include:

- macOS version
- Display configuration (resolution, scaling, ultrawide/superwide model)
- Steps to reproduce
- What you expected vs what actually happened

## Pull requests

- For anything non-trivial, open an issue first so we can agree on approach
  before you spend time on it.
- Keep PRs focused — one logical change per PR.
- Match the existing code style.
- Sign off your commits (see above).

---

## Developer Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I have the
    right to submit it under the open source license indicated in the
    file; or

(b) The contribution is based upon previous work that, to the best of my
    knowledge, is covered under an appropriate open source license and I
    have the right under that license to submit that work with
    modifications, whether created in whole or in part by me, under the
    same open source license (unless I am permitted to submit under a
    different license), as indicated in the file; or

(c) The contribution was provided directly to me by some other person who
    certified (a), (b) or (c) and I have not modified it.

(d) I understand and agree that this project and the contribution are
    public and that a record of the contribution (including all personal
    information I submit with it, including my sign-off) is maintained
    indefinitely and may be redistributed consistent with this project or
    the open source license(s) involved.
