ANONYMOUS;CODE Script Editor
============================================================

WHAT IT ADDS
------------
* Native name-box formatting and live character timelines
* Verified label-edge and exact after-dialogue-line story injection support
* Voice-block cataloging and selective local playback extraction
* Custom presentation mode for declaring the background, visible cast, positions, and show/hide state
* Speaker-focus timelines that remove inherited CG/camera/flashback choreography
* Explicit sprite coordinates and per-speaker visible-character groups
* Playing character voices
* A easy to use GUI editor


The engine still uses a native message window/checkpoint shell for text,
input, save, and transition behavior. Speakerfocus mode discards the shell's
visible CG, camera, effect, and character commands, so the scene's actual cast,
background, positions, and speaker visibility come from SOURCE/project.json. You can modify that if needed.


COMPATIBILITY
-------------
This build targets the English Steam release with the Committee of Zero
patch. You will need to supply your game files.
