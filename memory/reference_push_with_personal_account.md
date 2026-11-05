---
name: reference-push-with-personal-account
description: Pushing AlexTemina/* repos needs the personal GitHub account AlexTemina; the active gh account AlexTemina-alan gets 403
metadata:
  type: reference
---

Repos under `AlexTemina/` (this one included) belong to the personal GitHub account. The active `gh` account is the work one, `AlexTemina-alan`, so a plain `git push` fails with `403 ... denied to AlexTemina-alan`.

The personal account is logged into `gh` too, inactive. Push with its token, without switching the active account:

```sh
T=$(gh auth token --user AlexTemina) && git -c credential.helper= -c "credential.helper=!f() { echo username=AlexTemina; echo password=$T; }; f" push origin main; unset T
```

Creating a repo there: `GH_TOKEN=$(gh auth token --user AlexTemina) gh repo create AlexTemina/<name> ...`. It sets an SSH remote, which fails; switch it with `git remote set-url origin https://github.com/AlexTemina/<name>.git` before the first push.
