#!/bin/bash
set -euo pipefail
mkdir -p build
python3 -m unittest discover -s tools -p 'test_*.py' -v
swiftc App/AudioLearningCore.swift Tests/AudioLearningChecks.swift -o build/audio-learning-checks
build/audio-learning-checks
swiftc App/AudioLearningCore.swift App/AudioProgressStore.swift Tests/AudioProgressChecks.swift -o build/audio-progress-checks
build/audio-progress-checks
swiftc App/AudioLearningCore.swift App/AudioTutorProtocol.swift Tests/AudioProtocolChecks.swift -o build/audio-protocol-checks
build/audio-protocol-checks
swiftc App/SpeechLanguageRuns.swift Tests/SpeechLanguageChecks.swift -o build/speech-checks
build/speech-checks
bash -n ci/testflight.sh
