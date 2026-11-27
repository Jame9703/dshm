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

export interface DesktopVoiceMicrophone {
  id: number;
  type: number;
  name: string;
}

export class DesktopVoiceMicrophoneUnavailable extends Error {
  constructor() { super('Selected microphone is unavailable'); }
}

export function describeDesktopVoiceMicrophone(device: audio.AudioDeviceDescriptor): DesktopVoiceMicrophone {
  return { id: device.id, type: device.deviceType, name: device.displayName || device.name || '' };
}

export function resolveDesktopVoiceMicrophone(devices: audio.AudioDeviceDescriptors,
  selection: DesktopVoiceMicrophone): audio.AudioDeviceDescriptor | undefined {
  const matches = devices.filter((device: audio.AudioDeviceDescriptor): boolean =>
    device.deviceType === selection.type && describeDesktopVoiceMicrophone(device).name === selection.name);
  const known = matches.find((device: audio.AudioDeviceDescriptor): boolean => device.id === selection.id);
  return known ?? (selection.name && matches.length === 1 ? matches[0] : undefined);
}

export class DesktopVoiceCapture {
  private static active?: DesktopVoiceCapture;
  private capturer?: audio.AudioCapturer;
  private opened: Promise<void> = Promise.resolve();
  private releasing?: Promise<void>;
  private closed: boolean = false;
  private bytes: number = 0;
  private chunks: Uint8Array[] = [];
  private lastLevel: number = 0;
  private sessionRoute?: audio.AudioSessionManager;
  private previousInput?: audio.AudioDeviceDescriptor;
  private routedInput?: audio.AudioDeviceDescriptor;

  async start(maxBytes: number, onLevel: (value: number) => void,
    microphone?: DesktopVoiceMicrophone): Promise<boolean> {
    const releasing = DesktopVoiceCapture.active?.releasing;
    if (releasing !== undefined) { await releasing; }
    if (DesktopVoiceCapture.active !== undefined || this.closed) { return false; }
    DesktopVoiceCapture.active = this;
    this.opened = this.open(maxBytes, onLevel, microphone);
    await this.opened;
    return !this.closed;
  }

  constructor(onInterrupt: (microphoneLost?: boolean) => void) { this.interrupted = onInterrupt; }

  private readonly interrupted: (microphoneLost?: boolean) => void;

  private async selectMicrophone(microphone: DesktopVoiceMicrophone): Promise<audio.AudioDeviceDescriptor> {
    try {
      const routing = audio.getAudioManager().getSessionManager();
      const devices = routing.getAvailableDevices(audio.DeviceUsage.MEDIA_INPUT_DEVICES);
      const device = resolveDesktopVoiceMicrophone(devices, microphone);
      if (device !== undefined) {
        const previous = routing.getSelectedMediaInputDevice();
        if (previous.id !== device.id || previous.deviceType !== device.deviceType) {
          await routing.selectMediaInputDevice(device);
          this.sessionRoute = routing;
          this.previousInput = previous.deviceRole === audio.DeviceRole.INPUT_DEVICE ? previous : undefined;
          this.routedInput = device;
        }
        return device;
      }
    } catch (_) {}
    throw new DesktopVoiceMicrophoneUnavailable();
  }

  private async restoreMicrophone(): Promise<void> {
    const routing = this.sessionRoute;
    const routed = this.routedInput;
    if (routing === undefined || routed === undefined) { return; }
    try {
      const selected = routing.getSelectedMediaInputDevice();
      if (selected.id !== routed.id || selected.deviceType !== routed.deviceType) { return; }
      if (this.previousInput !== undefined) {
        try {
          await routing.selectMediaInputDevice(this.previousInput);
          return;
        } catch (_) {}
      }
      await routing.clearSelectedMediaInputDevice();
    } catch (_) {}
  }

  private async open(maxBytes: number, onLevel: (value: number) => void,
    microphone?: DesktopVoiceMicrophone): Promise<void> {
    const device = microphone === undefined ? undefined : await this.selectMicrophone(microphone);
    if (this.closed) { return; }
    const capturer = await audio.createAudioCapturer(OPTIONS);
    this.capturer = capturer;
    if (this.closed) { return; }
    if (device !== undefined) {
      capturer.on('inputDeviceChange', (devices: audio.AudioDeviceDescriptors): void => {
        if (!this.closed && !devices.some((input: audio.AudioDeviceDescriptor): boolean => input.id === device.id)) {
          this.interrupted(true);
        }
      });
    }
    capturer.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        this.interrupted();
      }
    });
    capturer.on('readData', (buffer: ArrayBuffer): void => {
      // A zero-byte budget monitors the input level without retaining audio.
      const remaining = maxBytes === 0 ? buffer.byteLength : maxBytes - this.bytes;
      const length = Math.floor(Math.min(buffer.byteLength, remaining) / 2) * 2;
      if (this.closed || length <= 0) { return; }
      if (maxBytes !== 0) {
        this.chunks.push(new Uint8Array(buffer, 0, length).slice());
        this.bytes += length;
      }
      const now = Date.now();
      if (now - this.lastLevel < 100) { return; }
      this.lastLevel = now;
      const values = new DataView(buffer);
      let energy = 0;
      let count = 0;
      for (let i = 0; i < length; i += 16) {
        const sample = values.getInt16(i, true) / 32768;
        energy += sample * sample;
        count++;
      }
      const level = Math.sqrt(energy / Math.max(1, count));
      onLevel(maxBytes === 0 ? level : Math.min(1, level * 5));
    });
    await capturer.start();
    if (device !== undefined && !this.closed) {
      const actual = capturer.getCurrentInputDevices();
      if (actual.length > 0 && !actual.some((input: audio.AudioDeviceDescriptor): boolean => input.id === device.id)) {
        throw new DesktopVoiceMicrophoneUnavailable();
      }
    }
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

  cancel(): Promise<void> {
    this.chunks = [];
    this.bytes = 0;
    return this.release();
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
        await this.restoreMicrophone();
        if (DesktopVoiceCapture.active === this) { DesktopVoiceCapture.active = undefined; }
      });
    }
    return this.releasing;
  }
}
