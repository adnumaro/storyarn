import type { SequenceVisualLayer } from "@modules/flows/sequence/types";
import type { PlayerAudioTrack } from "@modules/flows/player/components/PlayerAudioTracks.vue";
import type { ResponseData } from "@modules/flows/player/components/PlayerChoices.vue";
import type { SlideData } from "@modules/flows/player/components/PlayerSlide.vue";

export type SequencePlaybackAction = "start" | "stop" | "continue" | "choose" | "back" | "restart";

export interface SequencePlaybackState {
  slide: SlideData & { responses?: ResponseData[]; label?: string; node_id?: number };
  visualLayers: SequenceVisualLayer[];
  audioTracks: PlayerAudioTrack[];
  voice: { key: string; url: string } | null;
  canGoBack: boolean;
  showContinue: boolean;
  isFinished: boolean;
  error: string | null;
}
