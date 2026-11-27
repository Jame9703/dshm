import { audio } from '@kit.AudioKit';
import { HMS_SAMPLE_RATE } from 'appstate';
import { VOICE_WAV_HEADER_BYTES, voiceWavHeader } from './VoiceWave';

const OPTIONS: audio.AudioCapturerOptions = {
  streamInfo: {
    samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
    channels: audio.AudioChannel.CHANNEL_1,
    sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
    encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
  },
  capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
};

export class DesktopVoiceCapture {
  private static active?: DesktopVoiceCapture;
  private capturer?: audio.AudioCapturer;
  private opened: Promise<void> = Promise.resolve();
  private releasing?: Promise<void>;
  private closed: boolean = false;
  private bytes: number = 0;
  private chunks: Uint8Array[] = [];
  private lastLevel: number = 0;

  async start(maxBytes: number, onLevel: (value: number) => void): Promise<boolean> {
    if (DesktopVoiceCapture.active !== undefined || this.closed) { return false; }
    DesktopVoiceCapture.active = this;
    this.opened = this.open(maxBytes, onLevel);
    await this.opened;
    return !this.closed;
  }

  constructor(onInterrupt: () => void) { this.interrupted = onInterrupt; }

  private readonly interrupted: () => void;

  private async open(maxBytes: number, onLevel: (value: number) => void): Promise<void> {
    const capturer = await audio.createAudioCapturer(OPTIONS);
    this.capturer = capturer;
    if (this.closed) { return; }
    capturer.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        this.interrupted();
      }
    });
    capturer.on('readData', (buffer: ArrayBuffer): void => {
      const length = Math.floor(Math.min(buffer.byteLength, maxBytes - this.bytes) / 2) * 2;
      if (this.closed || length <= 0) { return; }
      const samples = new Uint8Array(buffer, 0, length).slice();
      this.chunks.push(samples);
      this.bytes += samples.length;
      const now = Date.now();
      if (now - this.lastLevel < 100) { return; }
      this.lastLevel = now;
      const values = new DataView(samples.buffer);
      let energy = 0;
      let count = 0;
      for (let i = 0; i < samples.length; i += 16) {
        const sample = values.getInt16(i, true) / 32768;
        energy += sample * sample;
        count++;
      }
      onLevel(Math.min(1, Math.sqrt(energy / Math.max(1, count)) * 5));
    });
    await capturer.start();
  }

  async finish(): Promise<Uint8Array | undefined> {
    await this.release();
    if (this.bytes < HMS_SAMPLE_RATE * 2 / 5) {
      this.chunks = [];
      this.bytes = 0;
      return undefined;
    }
    const wave = new Uint8Array(VOICE_WAV_HEADER_BYTES + this.bytes);
    wave.set(voiceWavHeader(this.bytes));
    let offset = VOICE_WAV_HEADER_BYTES;
    for (const chunk of this.chunks) {
      wave.set(chunk, offset);
      offset += chunk.length;
    }
    this.chunks = [];
    this.bytes = 0;
    return wave;
  }

  cancel(): void {
    this.chunks = [];
    this.bytes = 0;
    this.release();
  }

  private release(): Promise<void> {
    if (this.releasing === undefined) {
      this.closed = true;
      this.releasing = this.opened.catch((): void => {}).then(async (): Promise<void> => {
        const capturer = this.capturer;
        this.capturer = undefined;
        if (capturer !== undefined) {
          try { await capturer.stop(); } catch (_) {}
          try { await capturer.release(); } catch (_) {}
        }
        if (DesktopVoiceCapture.active === this) { DesktopVoiceCapture.active = undefined; }
      });
    }
    return this.releasing;
  }
}
