#!/usr/bin/env python3

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class SessionRoutingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="hxp-jump-routing-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.states = self.root / "runtime/hxp"
        self.states.mkdir(parents=True)
        tools = self.root / "bin"
        tools.mkdir()
        self.calls = self.root / "tmux-calls"
        (tools / "tmux").write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TMUX_CALLS"\n')
        (tools / "tmux").chmod(0o700)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root / "runtime"), TMUX_CALLS=str(self.calls),
                        PATH=str(tools) + ":" + os.environ["PATH"], HOME=str(self.root))
        for key in ("HXP_PREVIEW_SRC", "HXP_SESSION_SRC"):
            self.env.pop(key, None)

    def session(self, source, pane="", viewer="fancy-cat"):
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text("source\n")
        state = self.states / (hashlib.sha1(str(source).encode()).hexdigest() + ".state")
        targets = f"tmux={self.root}/tmux.sock,1,0\ntmux_pane={pane}\n" if pane else ""
        state.write_text(f"src={source}\neditor=helix\nviewer={viewer}\npid={os.getpid()}\n{targets}")

    def jump(self, target, **env):
        return subprocess.run([str(REPO / "bin/hxp-jump"), target], env=dict(self.env, **env),
                              capture_output=True, text=True)

    def sent_panes(self):
        calls = self.calls.read_text() if self.calls.exists() else ""
        return [call.split("-t ", 1)[1].split()[0] for call in calls.splitlines() if "send-keys" in call]

    def test_pinned_preview_never_borrows_another_editor(self):
        outer, inner = self.root / "book/main.typ", self.root / "book/part/main.typ"
        self.session(outer, pane="%1")
        self.session(inner)  # its editor is unreachable
        result = self.jump(f"{inner.parent / 'chapter.typ'}:2:1", HXP_PREVIEW_SRC=str(inner))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("could not reach the session editor", result.stderr)
        self.assertEqual(self.sent_panes(), [])

    def test_gui_viewer_environment_does_not_pin(self):
        # Sioyek retains its original environment.
        first, second = self.root / "a/main.tex", self.root / "b/main.tex"
        self.session(first, pane="%1", viewer="sioyek")
        self.session(second, pane="%2", viewer="sioyek")
        result = self.jump(f"{second}:3", HXP_SESSION_SRC=str(first))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.sent_panes()), {"%2"})


class ReloadNotificationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="hxp-reload-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.pdf = self.root / "source.pdf"
        self.pdf.write_text("old PDF\n")
        (self.root / "source.typ").write_text("Source.\n")
        tools = self.root / "bin"
        tools.mkdir()
        helper = tools / "fancy-cat"
        helper.write_text('''#!/usr/bin/python3
import json, os, pathlib, socket, sys
if os.environ.get("RELOAD_FAIL"):
    print("old fork", file=sys.stderr)
    sys.exit(2)
with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sender:
    payload = {"command": sys.argv[3:], "pdf": pathlib.Path(os.environ["RELOAD_PDF"]).read_text()}
    sender.sendto(json.dumps(payload).encode(), sys.argv[2])
''')
        helper.chmod(0o700)
        self.receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.addCleanup(self.receiver.close)
        self.receiver.bind(str(self.root / "preview.sock"))
        self.receiver.settimeout(0.05)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root / "runtime"),
                        PATH=str(tools) + ":" + os.environ["PATH"],
                        HXP_VIEWER_KIND="fancy-cat", HXP_VIEWER_SOCKET=str(self.root / "preview.sock"),
                        RELOAD_PDF=str(self.pdf))

    def shell(self, script, **env):
        return subprocess.run(["zsh", "-f", "-c", 'source "$1"; d="$2"; ' + script,
                               "hxp-reload-test", str(REPO / "zsh/hxp-lib.zsh"), str(self.root)],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def notification(self, text):
        self.assertEqual(json.loads(self.receiver.recv(8192)), {"command": ["reload"], "pdf": text})

    def no_notification(self):
        with self.assertRaises(socket.timeout):
            self.receiver.recv(8192)

    def test_only_the_session_socket_is_notified(self):
        other = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.addCleanup(other.close)
        other.bind(str(self.root / "other.sock"))
        other.settimeout(0.05)
        result = self.shell("_hxp_reload_viewer")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.notification("old PDF\n")
        with self.assertRaises(socket.timeout):
            other.recv(8192)

    def test_missing_or_older_viewers_leave_polling_available(self):
        for env in ({"HXP_VIEWER_KIND": "zathura"}, {"HXP_VIEWER_SOCKET": ""},
                    {"HXP_VIEWER_SOCKET": str(self.root / "gone.sock")}, {"RELOAD_FAIL": "1"}):
            result = self.shell("_hxp_reload_viewer", **env)
            self.assertEqual((result.returncode, result.stderr), (0, ""))
            self.no_notification()

    def test_generic_build_notifies_after_success_and_error_publication(self):
        script = r'''
_hxp_need_cmd() { [[ "$1" == typst ]] }
typst() { print -r -- '%PDF-good' > "${@[-1]}" }
_hxp_make_error_pdf() { print -r -- '%PDF-error' > "$5" }
compile() {
  _hxp_compile_once "$d/source.typ" typ "$d" source "$d/source.pdf" "$d/.tmp.pdf" \
    "$d/.error.log" "$d/.error.md" "$d/.debug.tex" "$d/.build"
}
compile || exit 9
typst() { return 1 }
compile
'''
        result = self.shell(script)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.notification("%PDF-good\n")
        self.notification("%PDF-error\n")
        self.no_notification()

    def test_native_watch_notifies_publications_and_preserves_last_good(self):
        script = r'''
print -r -- '%PDF-native' > "$d/.watch.pdf"
_hxp_make_error_pdf() { print -r -- '%PDF-error' > "$5" }
render() {
  _hxp_typst_render_state "$1" 'failure' "$d/source.typ" typ "$d/.error.log" "$d/.error.md" \
    "$d/.tmp.pdf" "$d/.debug.tex" "$d/source.pdf" "$d/.watch.pdf"
}
render ok || exit 9
render fail || exit 10
_hxp_make_error_pdf() { return 1 }  # --keep-last-good suppresses publication.
render fail
'''
        result = self.shell(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.notification("%PDF-native\n")
        self.notification("%PDF-error\n")
        self.no_notification()


class TypstStartupTests(unittest.TestCase):
    """The native watcher's first result is also the session's first build."""

    def run_session(self, initial="good", recover=False, fallback=False, keep=False,
                    disabled=False, watcher=None, abort=False, interrupt=False, replace_state=False, real=False):
        with tempfile.TemporaryDirectory(prefix="hxp-typst-startup-") as directory:
            root = Path(directory)
            tools = root / "bin"
            tools.mkdir()
            source = root / "source.typ"
            source.write_text(initial)
            (tools / "typst").write_text('''#!/usr/bin/python3
import os, pathlib, sys, time
root = pathlib.Path(os.environ["STARTUP_ROOT"])
with (root / "builds").open("a") as log:
    log.write(sys.argv[1] + "\\n")
(root / ("pid-" + str(os.getpid()))).touch()
if os.environ.get("STARTUP_INTERRUPT") == "1":
    time.sleep(60)
if sys.argv[1] == "watch" and os.environ.get("STARTUP_FALLBACK") == "1":
    sys.exit(2)
source, output = map(pathlib.Path, sys.argv[-2:])
previous = None
while True:
    text = source.read_text()
    if text != previous:
        previous = text
        print("[time] compiling ...", flush=True)
        if text == "error":
            print("error: startup failure", flush=True)
            print("[time] compiled with errors", flush=True)
        else:
            output.write_text("PDF-" + text)
            print("[time] compiled successfully", flush=True)
    if sys.argv[1] != "watch":
        sys.exit(1 if text == "error" else 0)
    time.sleep(.02)
''')
            if real:
                (tools / "typst").write_text(
                    '#!/usr/bin/python3\nimport os, pathlib, sys\n'
                    'root = pathlib.Path(os.environ["STARTUP_ROOT"])\n'
                    'with (root / "builds").open("a") as log: log.write(sys.argv[1] + "\\n")\n'
                    '(root / ("pid-" + str(os.getpid()))).touch()\n'
                    f'os.execv({shutil.which("typst")!r}, ["typst", *sys.argv[1:]])\n')
            (tools / "typst").chmod(0o700)
            # Reload requests prove the early watcher learns its eventual socket.
            (tools / "fancy-cat").write_text('''#!/usr/bin/python3
import json, os, pathlib, socket, sys
root = pathlib.Path(os.environ["STARTUP_ROOT"])
with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sender:
    sender.sendto(root.joinpath("source.pdf").read_bytes(), sys.argv[2])
root.joinpath("reloaded").touch()
''')
            (tools / "fancy-cat").chmod(0o700)
            receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            (root / "preview").mkdir()
            receiver.bind(str(root / "preview/socket"))
            receiver.settimeout(.1)
            script = r'''
source "$1/zsh/hxp-main.zsh"
source "$1/zsh/hxp-lib.zsh"
d="$STARTUP_ROOT"
_hxp_need_cmd() { return 0 }
typst() { exec "$STARTUP_ROOT/bin/typst" "$@" }
_hxp_viewer() { print fancy-cat }
_hxp_editor_window_id() { return 0 }
_hxp_start_split() {
  [[ "$STARTUP_ABORT" == 1 ]] && return 1
  preview_dir="$d/preview"
  cp "$pdf" "$d/first-preview"
}
_hxp_gui_viewer() { return 1 }
_hxp_release_split() { return 0 }
_hxp_cjk_font() { return 0 }
_hxp_make_error_pdf() {
  print -r -- error > "$4"
  [[ "${HXP_KEEP_LAST_GOOD:-}" == 1 ]] && return 1
  print -rn -- PDF-error > "$5"
}
_hxp_error_pos_for() { print -r -- "$src"$'\t1\t1' }
_hxp_editor_open() {
  print -r -- "$*" > "$d/editor"
  if [[ "$STARTUP_REPLACE_STATE" == 1 ]]; then
    print -rl -- viewer=fancy-cat "viewer_socket=$d/unrelated.sock" >| "$state_file"
  fi
  if [[ "$STARTUP_RECOVER" == 1 ]]; then
    print -rn -- recovered > "$src"
    for attempt in {1..200}; do
      [[ -e "$d/reloaded" ]] && return 0
      sleep .02
    done
    return 1
  fi
}
if [[ "$STARTUP_WATCHER" == session ]]; then
  hxp "$d/source.typ"
else
  HXP_STARTUP_RESULT="$d/ready" wpdf -q ${=STARTUP_WATCHER} "$d/source.typ" >/dev/null 2>&1 &
  watcher_pid=$!
  for attempt in {1..200}; do
    [[ -s "$d/ready" ]] && break
    [[ -s "$d/source.pdf" && "$STARTUP_FALLBACK" == 1 ]] && break
    sleep .02
  done
  [[ -s "$d/source.pdf" ]] || exit 1
  _hxp_stop_watcher "$watcher_pid"
  cp "$d/source.pdf" "$d/first-preview"
  : > "$d/editor"
fi
'''
            env = dict(os.environ, STARTUP_ROOT=str(root), XDG_RUNTIME_DIR=str(root / "runtime"),
                       PATH=str(tools) + ":" + os.environ["PATH"], STARTUP_RECOVER=str(int(recover)),
                       HXP_NO_NATIVE_TYP=str(int(disabled)), HXP_NO_WATCHEXEC="1", HXP_NO_TILE="1",
                       STARTUP_WATCHER="session" if watcher is None else watcher,
                       STARTUP_ABORT=str(int(abort)), STARTUP_INTERRUPT=str(int(interrupt)), STARTUP_FALLBACK=str(int(fallback)),
                       STARTUP_REPLACE_STATE=str(int(replace_state)))
            for name in ("HXP_KEEP_LAST_GOOD", "HXP_VIEWER_SOCKET", "HXP_VIEWER_KIND", "HXP_STARTUP_RESULT", "HXP_VIEWER_ROUTE"):
                env.pop(name, None)
            if fallback:
                env["STARTUP_FALLBACK"] = "1"
            if keep:
                env["HXP_KEEP_LAST_GOOD"] = "1"
                (root / "source.pdf").write_text("PDF-last-good")
            command = ["zsh", "-f", "-c", script, "startup-test", str(REPO)]
            if interrupt:
                process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    for _ in range(200):
                        if list(root.glob("pid-*")):
                            break
                        time.sleep(.01)
                    self.assertTrue(list(root.glob("pid-*")), "native build never started")
                    process.send_signal(signal.SIGTERM)
                    _, stderr = process.communicate(timeout=10)
                    self.assertNotEqual(process.returncode, 0, stderr)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            else:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 2 if abort else 0, result.stderr)
            for record in root.glob("pid-*"):
                pid = int(record.name[4:])
                for _ in range(100):
                    if not Path(f"/proc/{pid}").exists():
                        break
                    time.sleep(.01)
                self.assertFalse(Path(f"/proc/{pid}").exists(), f"orphaned Typst process {pid}")
            builds = (root / "builds").read_text().splitlines()
            self.assertFalse(list((root / "runtime/hxp").glob("watch.*")), "startup route directory leaked")
            first_bytes = (root / "first-preview").read_bytes() if (root / "first-preview").exists() else b""
            final_bytes = (root / "source.pdf").read_bytes() if (root / "source.pdf").exists() else b""
            if real:
                self.assertTrue(first_bytes.startswith(b"%PDF"))
                self.assertTrue(final_bytes.startswith(b"%PDF"))
                first, final = hashlib.sha256(first_bytes).hexdigest(), hashlib.sha256(final_bytes).hexdigest()
            else:
                first, final = first_bytes.decode(), final_bytes.decode()
            editor = (root / "editor").read_text() if (root / "editor").exists() else ""
            notifications = []
            try:
                while True:
                    payload = receiver.recv(1024 * 1024)
                    notifications.append(hashlib.sha256(payload).hexdigest() if real else payload.decode())
            except socket.timeout:
                pass
            finally:
                receiver.close()
            return builds, first, final, editor, notifications

    def test_first_success_builds_once_and_reuses_watcher(self):
        builds, first, final, _, notifications = self.run_session(recover=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual((first, final), ("PDF-good", "PDF-recovered"))
        self.assertEqual(notifications, ["PDF-recovered"])

    def test_first_error_opens_diagnostics_then_recovers(self):
        builds, first, final, editor, notifications = self.run_session(initial="error", recover=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual((first, final), ("PDF-error", "PDF-recovered"))
        self.assertIn(".source.error.log", editor)
        self.assertEqual(notifications, ["PDF-recovered"])

    def test_first_error_keeps_last_good(self):
        builds, first, final, editor, _ = self.run_session(initial="error", keep=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual((first, final), ("PDF-last-good", "PDF-last-good"))
        self.assertIn(".source.error.log", editor)

    def test_native_watch_failure_falls_back_to_one_shot(self):
        builds, first, final, _, _ = self.run_session(fallback=True)
        self.assertEqual(builds, ["watch", "compile"])
        self.assertEqual((first, final), ("PDF-good", "PDF-good"))

    def test_disabled_native_watch_keeps_one_shot_startup(self):
        builds, first, final, _, _ = self.run_session(disabled=True)
        self.assertEqual(builds, ["compile"])
        self.assertEqual((first, final), ("PDF-good", "PDF-good"))

    def test_standalone_native_watch_preserves_initial_build_option(self):
        for option in ("", "--no-initial"):
            with self.subTest(option=option):
                builds, first, final, _, _ = self.run_session(watcher=option)
                self.assertEqual(builds, ["compile", "watch"] if not option else ["watch"])
                self.assertEqual((first, final), ("PDF-good", "PDF-good"))

    def test_failed_viewer_launch_stops_the_early_watcher(self):
        builds, first, final, editor, _ = self.run_session(abort=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual((first, final, editor), ("", "PDF-good", ""))

    def test_interrupt_during_first_build_stops_the_early_watcher(self):
        builds, first, final, editor, _ = self.run_session(interrupt=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual((first, final, editor), ("", "", ""))

    def test_replaced_source_state_cannot_redirect_watcher_notifications(self):
        builds, _, final, _, notifications = self.run_session(recover=True, replace_state=True)
        self.assertEqual(builds, ["watch"])
        self.assertEqual(final, "PDF-recovered")
        self.assertEqual(notifications, ["PDF-recovered"])

    def test_standalone_default_retains_pdf_if_native_watch_exits_early(self):
        builds, first, final, _, _ = self.run_session(watcher="", fallback=True)
        self.assertEqual(builds[0], "compile")
        self.assertEqual((first, final), ("PDF-good", "PDF-good"))

    @unittest.skipUnless(shutil.which("typst"), "real Typst is required")
    def test_real_typst_first_build_and_edit_share_one_process(self):
        builds, first, final, _, notifications = self.run_session(recover=True, real=True)
        self.assertEqual(builds, ["watch"])
        self.assertNotEqual(first, final)
        self.assertEqual(notifications, [final])


class TypstForwardCacheTests(unittest.TestCase):
    def test_page_text_is_cached_per_build(self):
        with tempfile.TemporaryDirectory(prefix="hxp-fwd-cache-") as directory:
            root = Path(directory)
            source, pdf = root / "main.typ", root / "main.pdf"
            source.write_text("First line.\nUnique target phrase for forward search.\n")
            pdf.write_bytes(b"%PDF-1.4\n")
            states = root / "runtime/hxp"
            states.mkdir(parents=True)
            (states / (hashlib.sha1(str(source).encode()).hexdigest() + ".state")).write_text(
                f"src={source}\npdf={pdf}\nviewer=fancy-cat\npid={os.getpid()}\n"
                f"viewer_socket={root / 'preview.sock'}\n")
            receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            receiver.bind(str(root / "preview.sock"))
            self.addCleanup(receiver.close)
            tools = root / "bin"
            tools.mkdir()
            extracted, remote = root / "pdftotext-runs", root / "remote"
            (tools / "pdftotext").write_text(
                '#!/bin/sh\necho run >> "$EXTRACTED"\nprintf "Cover page\\fUnique target phrase for forward search.\\f"\n')
            (tools / "fancy-cat").write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$REMOTE"\n')
            for tool in tools.iterdir():
                tool.chmod(0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / "runtime"), EXTRACTED=str(extracted),
                       REMOTE=str(remote), PATH=f"{tools}:{REPO / 'bin'}:{os.environ['PATH']}")

            def search():
                result = subprocess.run([str(REPO / "bin/hxp-fwd"), str(source), "2", "1"], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(remote.read_text().split("\n")[2:4], ["goto-page", "2"])
                return len(extracted.read_text().split())

            self.assertEqual(search(), 1)
            self.assertEqual(search(), 1, "unchanged PDF was extracted again")
            pdf.write_bytes(b"%PDF-1.4\n% rebuilt\n")
            self.assertEqual(search(), 2, "rebuilt PDF reused stale page text")


@unittest.skipUnless(shutil.which("tmux"), "tmux is required")
class SearchTmuxTests(unittest.TestCase):
    def test_real_editors_open_quoted_source(self):
        for editor, binary in [("helix", "hx"), ("micro", "micro")]:
            with self.subTest(editor=editor), tempfile.TemporaryDirectory(prefix="hxp-editor-jump-") as directory:
                if not shutil.which(binary):
                    self.skipTest(f"{binary} is not installed")
                root = Path(directory)
                server = root / "tmux.sock"
                source = root / "main.typ"
                source.write_text("Initial source document.\n")
                target = root / 'chapter\'s "quoted"; file.typ'
                target.write_text("First target line.\nUnique target paragraph is visible here.\n")
                states = root / "runtime/hxp"
                states.mkdir(parents=True)
                env = dict(os.environ, XDG_RUNTIME_DIR=str(root/"runtime"), HXP_PREVIEW_SRC=str(source),
                           HOME=directory, XDG_CONFIG_HOME=str(root/"config"), TERM="xterm-256color")
                config = root / "editor-config"
                if editor == "helix":
                    config.write_text("[editor.lsp]\nenable = false\n")
                    command = [binary, "-c", str(config), str(source)]
                else:
                    config.mkdir()
                    command = [binary, "-config-dir", str(config), str(source)]

                def tmux(*args, check=True):
                    return subprocess.run(["tmux", "-S", str(server), *args], env=env,
                                          capture_output=True, text=True, check=check).stdout.strip()

                try:
                    pane = tmux("-f", "/dev/null", "new-session", "-dP", "-s", "editor", "-x", "140", "-y", "35",
                                "-F", "#{pane_id}", *command)
                    deadline = time.monotonic() + 5
                    while "Initial source document" not in tmux("capture-pane", "-pt", pane):
                        self.assertLess(time.monotonic(), deadline, tmux("capture-pane", "-pt", pane))
                        time.sleep(0.05)
                    pid = tmux("display-message", "-p", "#{pid}")
                    state = states / (hashlib.sha1(str(source).encode()).hexdigest()+".state")
                    state.write_text(f"src={source}\neditor={editor}\nviewer=fancy-cat\npid={os.getpid()}\n"
                                     f"tmux={server},{pid},0\ntmux_pane={pane}\n")
                    result = subprocess.run([str(REPO/"bin/hxp-jump"), f"{target}:2:1"], env=env,
                                            text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    deadline = time.monotonic() + 5
                    while "Unique target paragraph" not in tmux("capture-pane", "-pt", pane):
                        self.assertLess(time.monotonic(), deadline, tmux("capture-pane", "-pt", pane))
                        time.sleep(0.05)
                    screen = tmux("capture-pane", "-pt", pane)
                    self.assertIn("2:1" if editor == "helix" else "(2,1)", screen)
                finally:
                    tmux("kill-server", check=False)

    def test_literal_jump_and_forward_focus(self):
        with tempfile.TemporaryDirectory(prefix="hxp-search-tmux-") as directory:
            root = Path(directory)
            server = root / "tmux.sock"
            runtime = root / "runtime"
            (runtime / "hxp").mkdir(parents=True)
            source = root / "main.tex"
            source.write_text("root source\n")
            target = root / 'chapter "quoted"; file.tex'
            target.write_text("included source\n")
            recorded = root / "keys"
            reader = root / "reader.py"
            reader.write_text('''import os,sys,tty
from pathlib import Path
tty.setraw(0)
os.write(1,b"READY")
data=b""
while True:
    data+=os.read(0,4096)
    Path(sys.argv[1]).write_bytes(data)
''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HXP_PREVIEW_SRC=str(source),
                       TMUX="/nonexistent/other-server,1,0", TERM="xterm-256color")

            def tmux(*args, check=True):
                return subprocess.run(["tmux", "-S", str(server), *args], env=env,
                                      capture_output=True, text=True, check=check).stdout.strip()

            def wait_for(predicate):
                end = time.monotonic() + 5
                while time.monotonic() < end:
                    if predicate():
                        return
                    time.sleep(0.03)
                self.fail("private editor pane did not become ready")

            receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            receiver.bind(str(root / "preview.sock"))
            try:
                pane = tmux("-f", "/dev/null", "new-session", "-dP", "-s", "search", "-x", "120", "-y", "30",
                            "-F", "#{pane_id}", "python3", str(reader), str(recorded))
                viewer = tmux("split-window", "-hP", "-t", pane, "-F", "#{pane_id}", "sleep", "300")
                wait_for(lambda: "READY" in tmux("capture-pane", "-pt", pane))
                pid = tmux("display-message", "-p", "#{pid}")
                state = runtime / "hxp" / (hashlib.sha1(str(source).encode()).hexdigest() + ".state")
                state.write_text(f"src={source}\npdf={source.with_suffix('.pdf')}\neditor=helix\n"
                                 f"viewer=fancy-cat\npid={os.getpid()}\ntmux={server},{pid},0\n"
                                 f"tmux_pane={pane}\nviewer_pane={viewer}\nviewer_socket={root/'preview.sock'}\n")
                proxy_bin = root / "tmux-bin"
                proxy_bin.mkdir()
                tmux_calls = root / "tmux-calls.jsonl"
                proxy = proxy_bin / "tmux"
                proxy.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                                 'with open(os.environ["TMUX_CALLS"], "a") as calls:\n'
                                 '    calls.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                                 'os.execv(os.environ["REAL_TMUX"], ["tmux", *sys.argv[1:]])\n')
                proxy.chmod(0o700)
                jump_env = dict(env, PATH=str(proxy_bin)+":"+os.environ["PATH"],
                                REAL_TMUX=shutil.which("tmux"), TMUX_CALLS=str(tmux_calls))
                result = subprocess.run([str(REPO/"bin/hxp-jump"), f"{target}:2:1"], env=jump_env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                key_calls = [args for args in map(json.loads, tmux_calls.read_text().splitlines())
                             if "send-keys" in args]
                self.assertEqual(len(key_calls), 1, key_calls)
                wait_for(lambda: recorded.exists() and recorded.read_bytes().endswith(b"\r"))
                self.assertEqual(recorded.read_bytes(), f"\x1b\x1b:open '{target}:2:1'\r".encode())
                command = recorded.read_bytes().decode().lstrip("\x1b").strip()
                self.assertEqual(shlex.split(command), [":open", f"{target}:2:1"])
                self.assertEqual(tmux("display-message", "-p", "-t", pane, "#{pane_active}"), "1")

                tools = root / "bin"
                tools.mkdir()
                mock = tools / "fancy-cat"
                calls = root / "remote.json"
                mock.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                                'from pathlib import Path\nPath(os.environ["CALLS"]).write_text(json.dumps(sys.argv[1:]))\n')
                mock.chmod(0o700)
                source.with_suffix(".pdf").touch()
                env.update(PATH=str(tools)+":"+os.environ["PATH"], CALLS=str(calls))
                result = subprocess.run([str(REPO/"bin/hxp-fwd"), str(source), "2", "1"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(calls.read_text()),
                                 ["--remote", str(root/"preview.sock"), "forward-search", str(source), "2", "1"])
                self.assertEqual(tmux("display-message", "-p", "-t", viewer, "#{pane_active}"), "1")
                env["HOME"] = str(root)
                result = subprocess.run([str(REPO/"bin/hxp-fwd"), "~/main.tex", "2", "1"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(calls.read_text())[3], str(source))
            finally:
                receiver.close()
                tmux("kill-server", check=False)


if __name__ == "__main__":
    unittest.main()
