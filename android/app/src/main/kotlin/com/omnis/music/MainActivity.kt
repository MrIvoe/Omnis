package com.omnis.music

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the launcher activity to be (or extend)
// AudioServiceActivity — it overrides provideFlutterEngine() to reuse the
// background-persistent Flutter engine the media service needs to keep
// running after this activity is destroyed (screen off, app swiped away).
// A plain FlutterActivity here is why the notification's controls never
// worked even once the manifest declared the service/receiver.
class MainActivity: AudioServiceActivity()