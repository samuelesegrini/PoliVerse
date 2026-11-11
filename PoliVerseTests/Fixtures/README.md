# Subtitle fixture

`subtitles-en.mov` is a 34.66-second synthetic sample: a solid-color MJPEG video
and English speech generated locally with the macOS Samantha voice from
`subtitles-en.txt`. The audio track is tagged `en-US`. It contains no authored
subtitle track, network requests, course recordings or student information.

The asset belongs to the test bundle, not the shipping app. The opt-in
`RecordingSubtitlePlaybackTests` opens it through the production Mac player.
Its automated assertion verifies playback and fixture metadata. Inspecting the
native Language and Style menus and the generated words is a separate manual
check; a playback pass does not certify subtitle availability or accuracy.
