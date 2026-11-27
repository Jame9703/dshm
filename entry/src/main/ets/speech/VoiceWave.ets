import { HMS_SAMPLE_RATE } from 'appstate';

export const VOICE_WAV_HEADER_BYTES = 44;

export function voiceWavHeader(pcmBytes: number): Uint8Array {
  const header = new Uint8Array(VOICE_WAV_HEADER_BYTES);
  const view = new DataView(header.buffer);
  const tag = (at: number, value: string): void => {
    for (let i = 0; i < value.length; i++) { header[at + i] = value.charCodeAt(i); }
  };
  tag(0, 'RIFF');
  view.setUint32(4, pcmBytes + 36, true);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, HMS_SAMPLE_RATE, true);
  view.setUint32(28, HMS_SAMPLE_RATE * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  tag(36, 'data');
  view.setUint32(40, pcmBytes, true);
  return header;
}
