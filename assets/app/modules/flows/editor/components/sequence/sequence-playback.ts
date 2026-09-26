import type {
  SequenceVisualLayer,
  SequenceDialogueVoice,
  SequenceLanguageOption,
  SequenceLocalizationState,
} from "@modules/flows/sequence/types";
import type { PlayerAudioTrack } from "@modules/flows/player/components/PlayerAudioTracks.vue";

export interface SlideData {
  type: "dialogue" | "empty" | "outcome";
  // dialogue fields
  speaker_name?: string | null;
  speaker_initials?: string;
  speaker_avatar_url?: string | null;
  speaker_color?: string | null;
  text?: string;
  stage_directions?: string;
}

export interface ResponseData {
  id: string;
  text: string;
  valid: boolean;
  number: number;
  has_condition: boolean;
}

export type SequencePlaybackAction = "start" | "stop" | "continue" | "choose" | "back" | "restart";

export interface SequencePlaybackState {
  slide: SlideData & { responses?: ResponseData[]; label?: string; node_id?: number };
  visualLayers: SequenceVisualLayer[];
  audioTracks: PlayerAudioTrack[];
  voice: (SequenceDialogueVoice & { key: string; url: string }) | null;
  contentLocale?: string | null;
  languageOptions?: SequenceLanguageOption[];
  localizationStatus?: SequenceLocalizationState | null;
  canGoBack: boolean;
  showContinue: boolean;
  isFinished: boolean;
  error: string | null;
}
