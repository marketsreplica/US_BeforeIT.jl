#!/usr/bin/env python3

import io
import pathlib
import tarfile
import tempfile
import unittest

import generate_timezone_semantics as generator


class SafeExtractionTests(unittest.TestCase):
    def make_archive(self, archive_path, member_name, *, member_type=tarfile.REGTYPE):
        with tarfile.open(archive_path, "w") as archive:
            member = tarfile.TarInfo(member_name)
            member.type = member_type
            if member_type == tarfile.REGTYPE:
                payload = b"fixture"
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            else:
                archive.addfile(member)

    def assert_rejected(self, member_name, *, member_type=tarfile.REGTYPE):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            archive_path = root / "fixture.tar"
            destination = root / "out"
            destination.mkdir()
            self.make_archive(
                archive_path,
                member_name,
                member_type=member_type,
            )
            with tarfile.open(archive_path, "r") as archive:
                with self.assertRaises(SystemExit):
                    generator.safely_extract_source(archive, destination)

    def test_extracts_relative_regular_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            archive_path = root / "fixture.tar"
            destination = root / "out"
            destination.mkdir()
            self.make_archive(archive_path, "northamerica")
            with tarfile.open(archive_path, "r") as archive:
                generator.safely_extract_source(archive, destination)
            self.assertEqual((destination / "northamerica").read_bytes(), b"fixture")

    def test_rejects_posix_absolute_and_traversal_paths(self):
        for member_name in (
            "/escape",
            "../escape",
            "a/../../escape",
        ):
            with self.subTest(member_name=member_name):
                self.assert_rejected(member_name)

    def test_rejects_windows_drive_unc_rooted_and_traversal_paths(self):
        for member_name in (
            "C:/escape",
            r"C:\escape",
            r"C:escape",
            r"\escape",
            r"\\server\share\escape",
            r"a\..\escape",
        ):
            with self.subTest(member_name=member_name):
                self.assert_rejected(member_name)

    def test_rejects_links_and_special_members(self):
        for member_type in (
            tarfile.SYMTYPE,
            tarfile.LNKTYPE,
            tarfile.FIFOTYPE,
            tarfile.CHRTYPE,
            tarfile.BLKTYPE,
        ):
            with self.subTest(member_type=member_type):
                self.assert_rejected("unsafe-member", member_type=member_type)


if __name__ == "__main__":
    unittest.main()
