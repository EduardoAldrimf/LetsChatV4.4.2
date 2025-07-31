<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import debounce from 'lodash/debounce';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: Boolean,
  message: { type: Object, required: true },
});

const emit = defineEmits(['close', 'update:show']);
const store = useStore();
const { t } = useI18n();
const searchQuery = ref('');

const contacts = computed(() => store.getters['contacts/getContacts']);
const showEmptySearchResult = computed(
  () => !!searchQuery.value && contacts.value.length === 0
);

function updatePageParam(page) {
  window.history.pushState({}, null, `${window.location.pathname}?page=${page}`);
}

function fetchContacts(page) {
  updatePageParam(page);
  let value = searchQuery.value;
  if (value.startsWith('+')) {
    value = value.substring(1);
  }
  const requestParams = { page, sortAttr: '-last_activity_at' };
  if (!value) {
    store.dispatch('contacts/get', requestParams);
  } else {
    store.dispatch('contacts/search', {
      search: encodeURIComponent(value),
      ...requestParams,
    });
  }
}

const onInputSearch = debounce(event => {
  searchQuery.value = event.target.value;
  fetchContacts(1);
}, 300);

function resetSearch(event) {
  const newQuery = event.target.value;
  if (!newQuery) {
    searchQuery.value = newQuery;
    fetchContacts(1);
  }
}

function onSearchSubmit() {
  if (!searchQuery.value) return;
  fetchContacts(1);
}

function onSubmit(event) {
  const formData = new FormData(event.target);
  const contactIds = formData.getAll('contactIds[]');
  store.dispatch('forwardMessage', {
    conversationId: props.message.conversation_id,
    messageId: props.message.id,
    contacts: contactIds,
  });
  useAlert(t('FORWARD_MODAL.PROCESSING'));
  onClose();
}

function onClose() {
  emit('update:show', false);
  emit('close');
}
</script>

<template>
  <woot-modal v-model:show="props.show" modal-type="right-aligned" :on-close="onClose">
    <div class="fixed inset-y-0 right-0 max-h-screen overflow-auto bg-white shadow-md modal-container rtl:text-right dark:bg-slate-900 skip-context-menu rounded-xl w-[50rem] z-50">
      <div class="px-6 py-3 border-b border-slate-200 dark:border-slate-800">
        <h1 class="text-lg font-semibold text-slate-900 dark:text-white">
          {{ t('FORWARD_MODAL.TITLE') }}
        </h1>
        <p class="mt-1 text-xs text-slate-600 dark:text-slate-400">
          {{ t('FORWARD_MODAL.DESC') }}
        </p>
      </div>
      <div class="px-6 py-3 border-b border-slate-200 dark:border-slate-800">
        <label class="block text-xs font-medium text-slate-700 dark:text-slate-300 mb-1">
          {{ t('FORWARD_MODAL.SEARCH_LABEL') }}
        </label>
        <input
          type="search"
          class="w-full px-3 py-2 border border-slate-300 dark:border-slate-700 rounded-md focus:outline-none focus:ring-2 focus:ring-woot-500/20 focus:border-woot-500 bg-white dark:bg-slate-800 text-slate-900 dark:text-white hover:border-woot-500 transition-colors"
          v-model="searchQuery"
          @input="onInputSearch"
          @search="resetSearch"
          :placeholder="t('FORWARD_MODAL.SEARCH_PLACEHOLDER')"
        />
      </div>
      <form @submit.prevent="onSubmit" class="flex-1 flex flex-col min-h-0">
        <div class="px-6 py-2 bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700">
          <div class="flex items-center text-xs font-medium text-slate-700 dark:text-slate-300">
            <div class="w-6"></div>
            <div class="flex-1 min-w-[150px]">{{ t('FORWARD_MODAL.CONTACT') }}</div>
            <div class="w-36">{{ t('FORWARD_MODAL.PHONE') }}</div>
          </div>
        </div>
        <div class="flex-1 overflow-y-auto min-h-0">
          <div class="divide-y divide-slate-200 dark:divide-slate-700">
            <div
              v-for="contact in contacts"
              :key="contact.id"
              class="flex items-center px-6 py-2 hover:bg-slate-800/5 dark:hover:bg-slate-800"
            >
              <div class="w-6">
                <input
                  type="checkbox"
                  :value="contact.id"
                  name="contactIds[]"
                  class="w-4 h-4 rounded border-slate-300 dark:border-slate-600 text-woot-500 focus:ring-woot-500/20"
                />
              </div>
              <div class="flex-1 min-w-[150px] flex items-center">
                <div v-if="contact.thumbnail" class="w-6 h-6 mr-2">
                  <img :src="contact.thumbnail" :alt="contact.name" class="w-full h-full rounded-full object-cover" />
                </div>
                <span class="truncate text-xs">{{ contact.name }}</span>
              </div>
              <div class="w-36 truncate text-xs tracking-tight">{{ contact.phone_number }}</div>
            </div>
          </div>
        </div>
        <div class="px-6 py-3 bg-white dark:bg-slate-900 border-t border-slate-200 dark:border-slate-800 flex justify-end">
          <NextButton
            :disabled="showEmptySearchResult"
            class="bg-woot-500 hover:bg-woot-600 text-white text-sm px-4 py-1.5"
            >
            {{ t('FORWARD_MODAL.SUBMIT') }}
          </NextButton>
        </div>
      </form>
    </div>
  </woot-modal>
</template>
