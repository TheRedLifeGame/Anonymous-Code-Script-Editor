from __future__ import annotations

import copy
import unittest

from SOURCE.Editor.project_model import ensure_project, new_project, normalize_edge, validate_project


class ProjectModelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.project = new_project()

    def test_new_project_is_valid(self) -> None:
        self.assertEqual([], validate_project(self.project))

    def test_ensure_project_adds_optional_collections(self) -> None:
        project = {
            "schemaVersion": 2,
            "metadata": {"title": "Test", "version": "1.0"},
            "launchAlias": {"storage": "ac_00_01.ks", "sourceScene": "scene", "internalHash": "0" * 32},
            "scenes": [
                {
                    "id": "scene",
                    "title": "Scene",
                    "pages": [{"speaker": "", "text": "Text"}],
                }
            ],
        }

        result = ensure_project(project)

        self.assertEqual([], result["voiceCharacters"])
        self.assertEqual([], result["injections"])
        self.assertIsNone(result["scenes"][0]["next"])
        self.assertEqual("*start", result["scenes"][0]["template"]["target"])

    def test_normalize_edge_adds_default_target(self) -> None:
        edge = {"storage": "scene.ks", "target": ""}
        normalize_edge(edge)
        self.assertEqual("*start", edge["target"])

    def test_normalize_edge_preserves_explicit_target(self) -> None:
        edge = {"storage": "scene.ks", "target": "label"}
        normalize_edge(edge)
        self.assertEqual("*label", edge["target"])

    def test_duplicate_scene_ids_are_rejected(self) -> None:
        self.project["scenes"].append(copy.deepcopy(self.project["scenes"][0]))
        errors = validate_project(self.project)
        self.assertIn("Duplicate scene id: ac_ex_scene_01.", errors)

    def test_invalid_scene_fields_are_reported(self) -> None:
        scene = self.project["scenes"][0]
        scene["id"] = "not valid"
        scene["pages"][0]["text"] = ""
        scene["pages"][0]["window"] = "invalid"
        scene["presentation"]["music"] = "bad-id"
        errors = validate_project(self.project)

        self.assertTrue(any("id must use only ASCII" in error for error in errors))
        self.assertTrue(any("text is required" in error for error in errors))
        self.assertTrue(any("window must be dialogue or narration" in error for error in errors))
        self.assertTrue(any("music id contains invalid characters" in error for error in errors))

    def test_launch_scene_must_exist(self) -> None:
        self.project["launchAlias"]["sourceScene"] = "missing"
        self.assertIn(
            "GAME START scene must reference an existing scene id.",
            validate_project(self.project),
        )

    def test_after_line_injection_requires_text_and_resume_target(self) -> None:
        self.project["injections"] = [
            {
                "id": "branch",
                "kind": "afterLine",
                "source": {"storage": "base.ks", "target": "*start"},
                "expectedNext": {"storage": "next.ks", "target": "*start"},
                "destination": {"storage": "custom.ks", "target": "*start"},
                "line": {"text": ""},
                "resumeTarget": "resume",
            }
        ]

        errors = validate_project(self.project)

        self.assertIn("branch: after-line text is required.", errors)
        self.assertIn("branch: resume target must begin with *.", errors)


if __name__ == "__main__":
    unittest.main()
