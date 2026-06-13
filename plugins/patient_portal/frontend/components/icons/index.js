// Iconset interno do Portal do Paciente. Cada ícone é um component Vue
// que renderiza um <svg> stroke-based, herdando `currentColor`.
// Tamanho controlado via prop `size` (default 24).
//
// Por que SVG inline e não Iconify? O dashboard do Klivy usa Iconify, mas o
// SPA do portal é entry separado — evitamos a dependência extra. ~20 ícones
// resolvem todo o portal e adicionar mais é trivial (1 export).

import IconHome from './IconHome.vue';
import IconCalendar from './IconCalendar.vue';
import IconHeart from './IconHeart.vue';
import IconWallet from './IconWallet.vue';
import IconGrid from './IconGrid.vue';
import IconBell from './IconBell.vue';
import IconChevronRight from './IconChevronRight.vue';
import IconChevronLeft from './IconChevronLeft.vue';
import IconUser from './IconUser.vue';
import IconDocument from './IconDocument.vue';
import IconShield from './IconShield.vue';
import IconCheck from './IconCheck.vue';
import IconClose from './IconClose.vue';
import IconLogout from './IconLogout.vue';
import IconMessage from './IconMessage.vue';
import IconGift from './IconGift.vue';
import IconClock from './IconClock.vue';
import IconPill from './IconPill.vue';
import IconSparkle from './IconSparkle.vue';
import IconInfo from './IconInfo.vue';
// Sprint K — ícones da sala de telemedicina. Importados direto nos
// componentes da sala, mas exportados aqui pra manter o barrel consistente
// e permitir uso em outros pontos (ex: chip de teleconsulta no detalhe da
// consulta) via lookup no registry.
import IconVideo from './IconVideo.vue';
import IconVideoOff from './IconVideoOff.vue';
import IconMic from './IconMic.vue';
import IconMicOff from './IconMicOff.vue';
import IconPhoneHangup from './IconPhoneHangup.vue';
import IconScreenShare from './IconScreenShare.vue';
import IconSwitchCamera from './IconSwitchCamera.vue';

export {
  IconHome,
  IconCalendar,
  IconHeart,
  IconWallet,
  IconGrid,
  IconBell,
  IconChevronRight,
  IconChevronLeft,
  IconUser,
  IconDocument,
  IconShield,
  IconCheck,
  IconClose,
  IconLogout,
  IconMessage,
  IconGift,
  IconClock,
  IconPill,
  IconSparkle,
  IconInfo,
  IconVideo,
  IconVideoOff,
  IconMic,
  IconMicOff,
  IconPhoneHangup,
  IconScreenShare,
  IconSwitchCamera,
};

export const iconRegistry = {
  home: IconHome,
  calendar: IconCalendar,
  heart: IconHeart,
  wallet: IconWallet,
  grid: IconGrid,
  bell: IconBell,
  'chevron-right': IconChevronRight,
  'chevron-left': IconChevronLeft,
  user: IconUser,
  document: IconDocument,
  shield: IconShield,
  check: IconCheck,
  close: IconClose,
  logout: IconLogout,
  message: IconMessage,
  gift: IconGift,
  clock: IconClock,
  pill: IconPill,
  sparkle: IconSparkle,
  info: IconInfo,
  video: IconVideo,
  'video-off': IconVideoOff,
  mic: IconMic,
  'mic-off': IconMicOff,
  'phone-hangup': IconPhoneHangup,
  'screen-share': IconScreenShare,
  'switch-camera': IconSwitchCamera,
};
