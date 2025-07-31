<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import SoundCalling from 'dashboard/assets/audio/calling.mp3';
import SoundRinging from 'dashboard/assets/audio/ring.mp3';
import Thumbnail from '../Thumbnail.vue';
import Draggable from './Draggable.vue';
import Microphone from './icons/Microphone.vue';
import MicrophoneSlash from './icons/MicrophoneSlash.vue';
import VideoIcon from './icons/Video.vue';
import PhoneSlash from './icons/PhoneSlash.vue';
import NumpadVue from './icons/Numpad.vue';
import PhoneTransfer from './icons/PhoneTransfer.vue';
import Phone from './icons/Phone.vue';
import parsePhoneNumber from 'libphonenumber-js';

const store = useStore();

const elapsedTime = ref(0);
const timer = ref(null);
const isMuted = ref(false);
const callingSound = ref(null);
const ringSound = ref(null);
const localStream = ref(null);

const uiFlags = computed(() => store.getters['webphone/getUIFlags']);
const callInfo = computed(() => store.getters['webphone/getCallInfo']);
const inboxes = computed(() => store.getters['inboxes/getInboxes']);
const wavoip = computed(() => store.getters['webphone/getWavoip']);

const username = computed(
  () => callInfo.value.tag ?? callInfo.value.phone ?? ''
);
const isCallEndDisabled = computed(() =>
  ['terminate', 'reject', 'accept_elsewhere', 'reject_elsewhere'].includes(
    callInfo.value.status
  )
);
const formattedDuration = computed(() => {
  const minutes = Math.floor(elapsedTime.value / 60);
  const seconds = elapsedTime.value % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
});

function startWavoip(inboxName, token) {
  store.dispatch('webphone/startWavoip', { token, inboxName });
}

function startTimer() {
  if (timer.value) clearInterval(timer.value);
  const startDate = store.state.webphone.call.active_start_date;
  if (!startDate) return;
  timer.value = setInterval(() => {
    const now = new Date();
    elapsedTime.value = Math.floor((now - startDate) / 1000);
  }, 1000);
}

function stopTimer() {
  clearInterval(timer.value);
  timer.value = null;
  elapsedTime.value = 0;
}

function closeWebphone() {
  store.dispatch('webphone/updateWebphoneVisible', { isOpen: false });
}

function acceptCall() {
  store.dispatch('webphone/acceptCall');
}

function rejectCall() {
  store.dispatch('webphone/rejectCall');
}

function endCall() {
  store.dispatch('webphone/endCall');
}

function mute() {
  isMuted.value = true;
  if (localStream.value && localStream.value.getAudioTracks().length > 0) {
    localStream.value.getAudioTracks()[0].enabled = false;
  }
}

function unMute() {
  isMuted.value = false;
  if (localStream.value && localStream.value.getAudioTracks().length > 0) {
    localStream.value.getAudioTracks()[0].enabled = true;
  }
}

function listenSockets(token, whatsapp_instance) {
  if (!whatsapp_instance || !whatsapp_instance.socket) return;
  whatsapp_instance.socket.off('signaling');
  whatsapp_instance.socket.on('signaling', (...args) => {
    const data = args[0];
    store.dispatch('webphone/updateCallStatus', data?.tag);
    if (data?.tag === 'offer') {
      const name = data?.content?.from_tag;
      const whatsapp_id = data?.content?.phone;
      const phone =
        parsePhoneNumber(`+${whatsapp_id}`)?.formatInternational() ??
        whatsapp_id;
      const profile_picture = data?.content?.profile_picture;
      store.dispatch('webphone/incomingCall', {
        token,
        phone,
        contact_name: name,
        profile_picture,
      });
    } else if (
      ['terminate', 'reject', 'accept_elsewhere', 'reject_elsewhere'].includes(
        data?.tag
      )
    ) {
      setTimeout(() => {
        store.dispatch('webphone/resetCall');
      }, 3500);
    }
  });
}

function playCalling() {
  callingSound.value = new Audio(SoundCalling);
  callingSound.value.loop = true;
  callingSound.value.play();
}

function stopCalling() {
  if (callingSound.value) {
    callingSound.value.pause();
    callingSound.value.currentTime = 0;
  }
}

function playRinging() {
  ringSound.value = new Audio(SoundRinging);
  ringSound.value.loop = true;
  ringSound.value.play();
}

function stopRinging() {
  if (ringSound.value) {
    ringSound.value.pause();
    ringSound.value.currentTime = 0;
  }
}

watch(inboxes, newInboxes => {
  newInboxes.forEach(inbox => {
    if (inbox.external_token) {
      startWavoip(inbox.name, inbox.external_token);
    }
  });
});

watch(callInfo, newCallInfo => {
  const instances = store.state.webphone.wavoip;
  Object.keys(instances).forEach(token => {
    listenSockets(token, instances[token].whatsapp_instance);
  });
  const status = newCallInfo.status;
  if (status === 'accept') startTimer();
  else if (status === 'terminate') stopTimer();
  if (status === 'outcoming_calling') playCalling();
  else stopCalling();
  if (status === 'offer') playRinging();
  else stopRinging();
});

watch(wavoip, newWavoip => {
  Object.keys(newWavoip).forEach(token => {
    listenSockets(token, newWavoip[token].whatsapp_instance);
  });
});

onMounted(() => {
  // intentionally left blank
});
</script>

<template>
  <Draggable :initial-x="50" :initial-y="50">
    <div
      v-if="uiFlags.isOpen && callInfo.id && callInfo.status !== 'offer'"
      class="flex flex-col h-[315px] w-[250px] bg-white dark:bg-slate-900 opacity-90 border border-gray-500 rounded-xl select-none cursor-grab"
    >
      <div class="flex h-[30px] place-content-between items-center">
        <p class="text-xs text-slate-800 dark:text-slate-100 m-0 px-4">
          {{ callInfo.inbox_name }}
        </p>

        <button
          class="relative m-0 px-4 select-none rounded-lg bg-gray-900 text-center align-middle font-sans text-xs font-medium uppercase text-white transition-all hover:shadow-lg hover:shadow-gray-900/20 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none disabled:pointer-events-none disabled:opacity-50 disabled:shadow-none"
          type="button"
          data-ripple-light="true"
          @click="closeWebphone"
        >
          <span
            class="absolute transform -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
          >
            <fluent-icon
              icon="dismiss"
              size="14px"
              class="text-slate-800 dark:text-slate-100"
            />
          </span>
        </button>
      </div>
      <div class="flex justify-center align-middle mt-2">
        <Thumbnail
          :src="callInfo.picture_profile"
          :username="username"
          status="online"
          should-show-status-always
          size="64px"
        />
      </div>
      <div class="flex flex-col my-6">
        <p
          v-if="callInfo.tag"
          class="text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ callInfo.tag }}
        </p>
        <p v-else class="text-slate-800 dark:text-slate-100 m-0 text-center">
          {{ callInfo.phone }}
        </p>

        <p
          v-if="callInfo.status === 'accept'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ formattedDuration }}
        </p>
        <p
          v-if="callInfo.status === 'accept_elsewhere'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.ACCEPT_ELSEWHERE') }}
        </p>
        <p
          v-if="callInfo.status === 'reject_elsewhere'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.REJECT_ELSEWHERE') }}
        </p>
        <p
          v-if="callInfo.status === 'terminate'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.TERMINATE') }}
        </p>
        <p
          v-if="callInfo.status === 'reject'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.TERMINATE') }}
        </p>
        <p
          v-if="callInfo.status === 'outcoming_calling'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CONNECT_CALLING') }}
        </p>
        <p
          v-if="callInfo.status === 'preaccept'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CALLING') }}
        </p>
        <p
          v-if="callInfo.status === 'relaylatency'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CALLING') }}
        </p>
      </div>
      <div class="flex justify-center align-center gap-x-5 my-2">
        <span
          v-if="!isMuted"
          v-tooltip="$t('WEBPHONE.MUTE')"
          class="cursor-pointer text-slate-800 dark:text-slate-100 hover:text-slate-700 dark:hover:text-slate-300"
          @click="mute"
        >
          <Microphone :size="20" color="currentColor" />
        </span>
        <span
          v-else
          v-tooltip="$t('WEBPHONE.UNMUTE')"
          class="cursor-pointer text-red-300 hover:text-red-500"
          @click="unMute"
        >
          <MicrophoneSlash :size="20" color="currentColor" />
        </span>
        <span
          v-tooltip="$t('WEBPHONE.TURN_ON_VIDEO')"
          class="cursor-no-drop text-slate-600 dark:text-slate-300"
          :disabled="false"
        >
          <VideoIcon :size="20" color="currentColor" />
        </span>
        <span
          v-tooltip="$t('WEBPHONE.NUMPAD')"
          class="cursor-no-drop text-slate-600 dark:text-slate-300"
        >
          <NumpadVue :size="20" color="currentColor" />
        </span>
        <span
          v-tooltip="$t('WEBPHONE.TRANSFER')"
          class="cursor-no-drop text-slate-600 dark:text-slate-300"
        >
          <PhoneTransfer :size="20" color="currentColor" />
        </span>
      </div>
      <div class="flex justify-center align-center my-4">
        <button
          class="relative h-15 max-h-[30px] w-15 max-w-[30px] p-[17px] select-none rounded-full bg-red-500 text-center align-middle font-sans text-xs font-medium uppercase text-white shadow-md shadow-gray-900/10 transition-all hover:shadow-lg hover:shadow-gray-900/20 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none disabled:pointer-events-none disabled:opacity-50 disabled:shadow-none"
          type="button"
          data-ripple-light="true"
          :disabled="isCallEndDisabled"
          @click="endCall"
        >
          <span
            class="absolute transform -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
          >
            <PhoneSlash :size="15" color="white" />
          </span>
        </button>
      </div>
    </div>
    <div
      v-if="uiFlags.isOpen && callInfo.id && callInfo.status === 'offer'"
      class="flex flex-col h-[315px] w-[250px] bg-white dark:bg-slate-900 opacity-90 border border-gray-500 rounded-xl select-none cursor-grab"
    >
      <div class="flex h-[30px] place-content-between items-center">
        <p class="text-xs text-slate-800 dark:text-slate-100 m-0 px-4">
          {{ callInfo.inbox_name }}
        </p>

        <button
          class="relative m-0 px-4 select-none rounded-lg bg-gray-900 text-center align-middle font-sans text-xs font-medium uppercase text-white transition-all hover:shadow-lg hover:shadow-gray-900/20 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none disabled:pointer-events-none disabled:opacity-50 disabled:shadow-none"
          type="button"
          data-ripple-light="true"
          @click="closeWebphone"
        >
          <span
            class="absolute transform -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
          >
            <fluent-icon
              icon="dismiss"
              size="14px"
              class="text-slate-800 dark:text-slate-100"
            />
          </span>
        </button>
      </div>
      <div class="flex justify-center align-middle mt-2">
        <Thumbnail
          :src="callInfo.picture_profile"
          :username="username"
          status="online"
          should-show-status-always
          size="64px"
        />
      </div>
      <div class="flex flex-col my-6">
        <p
          v-if="callInfo.tag"
          class="text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ callInfo.tag }}
        </p>
        <p v-else class="text-slate-800 dark:text-slate-100 m-0 text-center">
          {{ $t('WEBPHONE.UNKNOWN') }}
        </p>

        <p
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ callInfo.phone }}
        </p>
        <p
          v-if="callInfo.status === 'terminate'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.TERMINATE') }}
        </p>
        <p
          v-if="callInfo.status === 'reject'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.TERMINATE') }}
        </p>
        <p
          v-if="callInfo.status === 'outcoming_calling'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CONNECT_CALLING') }}
        </p>
        <p
          v-if="callInfo.status === 'preaccept'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CALLING') }}
        </p>
        <p
          v-if="callInfo.status === 'relaylatency'"
          class="text-lg font-medium text-slate-800 dark:text-slate-100 m-0 text-center"
        >
          {{ $t('WEBPHONE.CALLING') }}
        </p>
      </div>
      <div class="flex justify-center align-center my-4 gap-x-4">
        <button
          class="relative h-15 max-h-[30px] w-15 max-w-[30px] p-[17px] select-none rounded-full bg-green-500 text-center align-middle font-sans text-xs font-medium uppercase text-white shadow-md shadow-gray-900/10 transition-all hover:shadow-lg hover:shadow-gray-900/20 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none disabled:pointer-events-none disabled:opacity-50 disabled:shadow-none"
          type="button"
          data-ripple-light="true"
          :disabled="isCallEndDisabled"
          @click="acceptCall"
        >
          <span
            class="absolute transform -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
          >
            <Phone :size="15" color="white" />
          </span>
        </button>
        <button
          class="relative h-15 max-h-[30px] w-15 max-w-[30px] p-[17px] select-none rounded-full bg-red-500 text-center align-middle font-sans text-xs font-medium uppercase text-white shadow-md shadow-gray-900/10 transition-all hover:shadow-lg hover:shadow-gray-900/20 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none disabled:pointer-events-none disabled:opacity-50 disabled:shadow-none"
          type="button"
          data-ripple-light="true"
          :disabled="isCallEndDisabled"
          @click="rejectCall"
        >
          <span
            class="absolute transform -translate-x-1/2 -translate-y-1/2 top-1/2 left-1/2"
          >
            <PhoneSlash :size="15" color="white" />
          </span>
        </button>
      </div>
    </div>
  </Draggable>
</template>
