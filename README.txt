ANONYMOUS;CODE PATCHING GUIDE
Unofficial developer tutorial, version 1.0.0
============================================================

WHAT IT ADDS
------------
* One in-game tutorial scene with page count generated from SOURCE/project.json
* Pollon, Momo, Cross, and Wind speaking directly to you
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
This build targets the English Steam release with the required Committee of Zero
patch. You will need to supply your game files.
