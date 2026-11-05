# Polish round 6 — working brief for section agents

You are doing **one section** of polish round 6 on Canadian Winter. The coordinator gives you the
section. Read, in this order:

1. `CLAUDE.md` (repo root) — the rules every agent follows.
2. `docs/polish6/STATUS.md` — commits so far, open items, and **binding notes** from earlier
   sections. Binding notes are rules for you.
3. `docs/polish6/POLISH_ROUND_6_PROMPT.md` — the round's brief. Read its **Decisions**, **§0 Ground
   rules** and **your section** in full. Your section's checkboxes and *Done when / tests* list are
   the definition of done.
4. Whatever the brief tells you to read for your section (`HANDOFF.md`, `docs/polish5/…`).

## This machine (the owner's Windows PC) — differs from the brief

- **Repo:** `C:/Users/orsin/OneDrive/Desktop/Canadian Winter/Canadian-Winter` (Bash:
  `/c/Users/orsin/OneDrive/Desktop/Canadian Winter/Canadian-Winter`). Always quote the path.
- **Branch:** `wc-polish6-pg` (the owner named it; it stands in for the brief's `wc-polish6`).
  **Commits stay local. Never push, never open a PR, never touch `main`, never create/delete
  branches or tags unless your section says so.** The coordinator handles pushing later with the
  owner's OK.
- **"CI green" means the local equivalent:** import, `parse_all`, and the suites your change can
  affect pass here. The coordinator runs the full suite between sections.
- **Godot:** start every Bash command that runs Godot with
  `export PATH="/c/Users/orsin/AppData/Local/Temp/claude/8a7df22634b74fee/8cef635c-7f04-41ab-a9b1-cd462e6c7b0e/scratchpad/tools:$PATH"`
  then call `godot …` exactly as in `CLAUDE.md`. The wrapper is the 4.7.2 console build and
  **serializes Godot runs with a lock** (it waits if another run holds it). Never bypass it and
  never run Godot in the background while starting another.
- **The owner's real saves and settings** live in `%APPDATA%/Godot/app_userdata/Canadian Winter/`
  and the owner plays on this PC. The wrapper points Godot's `user://` at a scratch folder
  (`…/scratchpad/appdata/Godot/app_userdata/Canadian Winter/`) by setting `APPDATA`, so tests,
  fixtures and benches can't overwrite or delete the owner's saves. Always run Godot through the
  wrapper; never read, write or delete anything in the real folder.
- **Bash timeout** is 10 minutes max per foreground command. Run the test runner one suite at a
  time (`-- --only=<suite>`, `--test=<part>`); the full runner is longer than 10 minutes. Write
  long output to a file and `grep`/`tail` it rather than printing it all.
- **Screenshots:** no `xvfb-run` here — the PC has a real GPU (GTX 1070) and screen. Run windowed:
  `godot --path . --resolution 1920x1080 res://tests/shot.tscn -- --scene=game --out=<png> [options]`
  (a window opens briefly; the capture comes out 1600×900, which is fine). Save scratch PNGs in
  your scratchpad, **look at every shot with Read**, and convert the ones you keep to 1280-px JPEG:
  `powershell -NoProfile -File "C:/Users/orsin/AppData/Local/Temp/claude/8a7df22634b74fee/8cef635c-7f04-41ab-a9b1-cd462e6c7b0e/scratchpad/tools/tojpg.ps1" <in.png> <out.jpg>`
  into `docs/polish6/shots/<NN>-<name>/before_*.jpg` / `after_*.jpg`.
- **"Before" shots and baseline numbers** come from the read-only baseline worktree at
  `C:/Users/orsin/AppData/Local/Temp/claude/8a7df22634b74fee/8cef635c-7f04-41ab-a9b1-cd462e6c7b0e/scratchpad/baseline`
  (tag `polish6-baseline` = `1b38f4a`). Never edit or commit there. Baseline logs are in
  `docs/polish6/baseline/`.
- **Line endings:** `core.autocrlf=true`, no `.gitattributes` (until §2 decides). Write files with
  LF; git normalizes on commit. Don't commit whole-file line-ending churn.
- **The owner may open the Godot editor** on this project. If a run behaves oddly, check
  `tasklist | grep -i godot`; never kill a process you didn't start — report it instead.
- No Python imaging libraries; don't install packages. Python 3.11 is available for
  `tools/audio/gen_audio.py` if it needs only the standard library (check first).

## How to do your section

1. **Audit / measure first** exactly as the section says, and write the numbers down.
2. Implement only what the section lists, the way the game already does things (`CLAUDE.md`,
   *Don't change the game*). Protected behaviour stays protected; if your item needs it changed,
   stop that item and report it.
3. Tests: new ones in `tests/test_polish6.gd` (`--only=polish6`), grouped under a comment header
   for your section. Tests the brief says change are updated through lookups, never deleted,
   skipped or loosened. Run every suite your change can touch.
4. New scripts: run the import (`godot --headless --path . --editor --quit`) so the `.uid` exists,
   and commit it.
5. Screenshots for every visual change, before/after, looked at.
6. Write `docs/polish6/report/s<N>.md`: each checkbox as done / partly / not done with one line on
   how it was verified; the audit; numbers before → after; readings you took; anything reverted or
   left open and why.
7. Add your binding notes and open items to `docs/polish6/STATUS.md` (things later sections must
   respect: new balance keys, new actions, function names, gotchas).
8. **One commit** for the section: `polish6 §<N>: <title>`, ending with the line
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. If you fix things after review,
   amend that same commit (it's local and unpushed).
9. Your final answer: what you did, every test/bench result with numbers, what's not done and why,
   the commit hash.
