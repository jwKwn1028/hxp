#!/usr/bin/env python3

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InverseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hxp-inverse-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.source = self.project / "main.typ"
        self.source.write_text("= Heading\n\nDistinctive quantum prose in the document.\n")
        self.pdf = self.source.with_suffix(".pdf")
        self.pdf.touch()
        runtime = self.root / "runtime"
        states = runtime / "hxp"
        states.mkdir(parents=True)
        key = hashlib.sha1(str(self.source).encode()).hexdigest()
        self.state = states / f"{key}.state"
        self.state.write_text(f"src={self.source}\npdf={self.pdf}\npid={os.getpid()}\n")
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HXP_PREVIEW_SRC=str(self.source))

    def lookup(self, text, code=0):
        result = subprocess.run([str(REPO / "bin/hxp-inverse"), str(self.pdf), "1", "100", "100", text],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stderr)
        if code:
            self.assertEqual(result.stdout, "")
            return result.stderr
        file, line, column = result.stdout.strip().rsplit(":", 2)
        return Path(file), int(line), int(column)

    def test_prose_location(self):
        self.assertEqual(self.lookup("Distinctive quantum prose in the document."), (self.source, 3, 1))

    def test_markup_and_wrapped_source(self):
        self.source.write_text("First line.\nDistinctive *quantum* prose\nin the document.\n")
        self.assertEqual(self.lookup("Distinctive quantum prose in the document."), (self.source, 2, 1))

    def test_ligatures_and_punctuation(self):
        self.source.write_text("An efficient office works precisely.\n")
        self.assertEqual(self.lookup("An eﬃcient oﬃce works precisely."), (self.source, 1, 1))

    def test_korean_text(self):
        self.source.write_text("= 머리말\n서로 다른 문장을 정확히 찾아갑니다.\n")
        self.assertEqual(self.lookup("서로 다른 문장을 정확히 찾아갑니다."), (self.source, 2, 1))

    def test_literal_include_with_quotes_in_path(self):
        self.source.write_text('#include "chapter\'s notes.typ"\n')
        included = self.project / "chapter's notes.typ"
        included.write_text("A uniquely identifiable included paragraph.\n")
        self.assertEqual(self.lookup("A uniquely identifiable included paragraph."), (included, 1, 1))

    def test_commented_include_and_unrelated_file_are_ignored(self):
        self.source.write_text('// #include "unrelated.typ"\n')
        (self.project / "unrelated.typ").write_text("Distinctive quantum prose in the document.\n")
        self.lookup("Distinctive quantum prose in the document.", 3)

    def test_comments_and_code_are_not_prose(self):
        self.source.write_text('// Distinctive quantum prose in the document.\n'
                               '#let hidden = "Distinctive quantum prose in the document."\n')
        self.lookup("Distinctive quantum prose in the document.", 3)

    def test_repeated_text_is_ambiguous(self):
        self.source.write_text("Repeated distinctive quantum prose.\n\nRepeated distinctive quantum prose.\n")
        self.assertIn("more than once", self.lookup("Repeated distinctive quantum prose.", 4))

    def test_neighboring_text_disambiguates(self):
        self.source.write_text("Repeated distinctive prose with first context.\n\n"
                               "Repeated distinctive prose with second context.\n")
        self.assertEqual(self.lookup("Repeated distinctive prose with second context."), (self.source, 3, 1))

    def test_blank_and_unmatched_text(self):
        self.lookup("", 3)
        self.lookup("A completely different sentence is displayed.", 3)

    def test_stale_and_reused_pid_are_rejected(self):
        self.state.write_text(f"src={self.source}\npdf={self.pdf}\npid={os.getpid()}\npid_start=0\n")
        self.lookup("Distinctive quantum prose in the document.", 5)

    def test_session_must_own_the_pdf(self):
        self.state.write_text(f"src={self.source}\npdf={self.project / 'other.pdf'}\npid={os.getpid()}\n")
        self.lookup("Distinctive quantum prose in the document.", 5)

    def test_glob_fallback_without_preview_pin(self):
        del self.env["HXP_PREVIEW_SRC"]
        self.assertEqual(self.lookup("Distinctive quantum prose in the document."), (self.source, 3, 1))

    def test_root_relative_and_code_block_includes(self):
        self.source.write_text('#include "/parts/a.typ"\n#{\n  include "b.typ"\n}\n')
        (self.project / "parts").mkdir()
        first, second = self.project / "parts/a.typ", self.project / "b.typ"
        first.write_text("A uniquely identifiable root relative paragraph.\n")
        second.write_text("Another identifiable paragraph from a code block.\n")
        self.assertEqual(self.lookup("A uniquely identifiable root relative paragraph."), (first, 1, 1))
        self.assertEqual(self.lookup("Another identifiable paragraph from a code block."), (second, 1, 1))

    def test_prose_include_words_are_not_dependencies(self):
        self.source.write_text('We include "b.typ" in prose only.\n')
        (self.project / "b.typ").write_text("Another identifiable paragraph from a code block.\n")
        self.lookup("Another identifiable paragraph from a code block.", 3)

    def test_unpaired_prose_quote_keeps_comments_hidden(self):
        self.source.write_text('A 12" ruler is long.\n// Secret commented sentence nobody renders.\n'
                               '/* Another hidden block sentence here. */\n')
        self.lookup("Secret commented sentence nobody renders.", 3)
        self.lookup("Another hidden block sentence here.", 3)

    def test_links_and_escaped_dollars_stay_prose(self):
        self.source.write_text("See https://example.org for distinctive quantum prose.\n"
                               "It costs \\$5 today.\nDistinctive middle sentence stays visible.\nAnd \\$6 later.\n")
        self.assertEqual(self.lookup("See https://example.org for distinctive quantum prose."), (self.source, 1, 1))
        self.assertEqual(self.lookup("Distinctive middle sentence stays visible."), (self.source, 3, 1))

    def test_multiline_code_strings_are_not_prose(self):
        self.source.write_text('#let note = (\n  body: "Distinctive quantum prose here.",\n)\n'
                               '#set text(\n  lang: "en",\n)\nDistinctive quantum prose here.\n')
        self.assertEqual(self.lookup("Distinctive quantum prose here."), (self.source, 7, 1))

    def test_content_arguments_are_prose(self):
        self.source.write_text('#figure(image("a.png"), caption: [A caption about quantum lattices.])\n')
        self.assertEqual(self.lookup("Figure 1: A caption about quantum lattices."), (self.source, 1, 35))

    def test_generated_text_inside_a_line(self):
        self.source.write_text("Prior careful work on lattice models @smith2020 shows strong ordering at low temperature.\n")
        self.assertEqual(self.lookup("Prior careful work on lattice models (Smith and Jones, 2020) "
                                     "shows strong ordering at low temperature."), (self.source, 1, 1))

    def test_separated_partial_matches_stay_ambiguous(self):
        self.source.write_text("Prior careful work on lattice models appears here.\n\n" + "Filler words. " * 40 +
                               "\n\nElsewhere it shows strong ordering at low temperature.\n")
        self.lookup("Prior careful work on lattice models shows strong ordering at low temperature.", 4)

    def test_cjk_text_wrapped_in_source(self):
        self.source.write_text("这是一个用于测试的中文句子，它在源文件中\n被换行了但是在文档里不是。\n")
        self.assertEqual(self.lookup("中文句子，它在源文件中被换行了"), (self.source, 1, 10))

    def test_invalid_position(self):
        result = subprocess.run([str(REPO / "bin/hxp-inverse"), str(self.pdf), "1", "nan", "1", "x"],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2, result.stderr)

    def synctex_state(self):
        tex = self.source.with_suffix(".tex")
        tex.write_text("\\documentclass{article}\n")
        key = hashlib.sha1(str(tex).encode()).hexdigest()
        (self.state.parent / f"{key}.state").write_text(f"src={tex}\npdf={self.pdf}\npid={os.getpid()}\n")
        self.env["HXP_PREVIEW_SRC"] = str(tex)
        tools = self.root / "tools"
        tools.mkdir()
        (tools / "python3").symlink_to(shutil.which("python3"))
        self.env["PATH"] = str(tools)
        return tools

    def test_synctex_miss_and_missing_tool_codes(self):
        tools = self.synctex_state()
        self.assertIn("synctex is not installed", self.lookup("", 1))
        (tools / "synctex").write_text("#!/bin/sh\necho 'SyncTeX result begin'\necho 'SyncTeX result end'\n")
        (tools / "synctex").chmod(0o700)
        self.assertIn("no SyncTeX source location", self.lookup("", 6))

    @unittest.skipUnless(shutil.which("pdflatex") and shutil.which("synctex"), "TeX tools are required")
    def test_real_synctex_location(self):
        tex = self.source.with_suffix(".tex")
        tex.write_text("\\documentclass{article}\n\\begin{document}\n"
                       "Distinctive quantum prose in the document.\n\\end{document}\n")
        subprocess.run(["pdflatex", "-synctex=1", "-interaction=batchmode", tex.name],
                       cwd=self.project, capture_output=True, check=True)
        key = hashlib.sha1(str(tex).encode()).hexdigest()
        (self.state.parent/f"{key}.state").write_text(f"src={tex}\npdf={self.pdf}\npid={os.getpid()}\n")
        self.env["HXP_PREVIEW_SRC"] = str(tex)
        view = subprocess.run(["synctex", "view", "-i", f"3:1:{tex}", "-o", str(self.pdf)],
                              text=True, capture_output=True, check=True).stdout
        values = [re.search(r"^"+name+r":(.+)$", view, re.MULTILINE)[1] for name in ["Page", "x", "y"]]
        result = subprocess.run([str(REPO/"bin/hxp-inverse"), str(self.pdf), *values, ""],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        file, line, column = result.stdout.strip().rsplit(":", 2)
        self.assertEqual((Path(file), int(line)), (tex, 3))
        self.assertGreaterEqual(int(column), 1)


if __name__ == "__main__":
    unittest.main()
