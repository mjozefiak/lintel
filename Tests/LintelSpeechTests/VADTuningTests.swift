import FluidAudio
import Testing

@testable import LintelSpeech

@Suite struct VADTuningTests {
    /// Dictation keeps FluidAudio's defaults; if a FluidAudio update changes them, this says so before dictation
    /// silently changes behaviour.
    @Test func standardTuningIsFluidAudiosDefault() {
        let tuning = VADTuning.standard
        #expect(tuning.entryThreshold == VadConfig.default.defaultThreshold)
        let segmentation = VadSegmentationConfig.default
        #expect(tuning.exitOffset == segmentation.negativeThresholdOffset)
        #expect(tuning.minSilence == segmentation.minSilenceDuration)
        #expect(tuning.padding == segmentation.speechPadding)
    }

    @Test func aDetectorWithoutProbabilitiesReturnsNone() async {
        struct Plain: VoiceActivityDetector {
            func process(_ samples: [Float]) async throws -> [VADEvent] { [] }
        }
        #expect(await Plain().drainProbabilities().isEmpty)
    }
}
