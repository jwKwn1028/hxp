#!/usr/bin/env python3
"""Source/PDF routing with private tmux servers."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class SessionRoutingTests(unittest.TestCase):
    """Record editor routing through mock tmux."""

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


class TypstForwardCacheTests(unittest.TestCase):
    """Cache page text until the PDF changes."""

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
