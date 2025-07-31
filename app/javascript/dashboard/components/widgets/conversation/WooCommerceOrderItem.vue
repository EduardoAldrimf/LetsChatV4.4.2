<script setup>
import { computed } from 'vue';
import { format } from 'date-fns';
import { useI18n } from 'vue-i18n';

const { order } = defineProps({
  order: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const paymentStatus = computed(() => {
  if (!order.status) return '';
  return t(
    `CONVERSATION_SIDEBAR.WOOCOMMERCE.PAYMENT_STATUS.${order.status.toUpperCase()}`
  );
});

const statusClass = computed(() => {
  const classes = {
    pending: 'bg-n-amber-3 text-n-amber-11',
    processing: 'bg-n-teal-5 text-n-teal-12',
    'on-hold': 'bg-n-iris-3 text-n-iris-11',
    completed: 'bg-n-teal-5 text-n-teal-12',
    cancelled: 'bg-n-ruby-5 text-n-ruby-12',
    refunded: 'bg-n-ruby-5 text-n-ruby-12',
    failed: 'bg-n-ruby-5 text-n-ruby-12',
  };
  return classes[order.status] || 'bg-n-slate-3 text-n-slate-11';
});

const formatDate = dateString => format(new Date(dateString), 'MMM d, yyyy');
const formatCurrency = (amount, currency) =>
  new Intl.NumberFormat('en', { style: 'currency', currency }).format(amount);
</script>

<template>
  <div
    class="py-3 border-b border-n-weak last:border-b-0 flex flex-col gap-1.5"
  >
    <div class="flex justify-between items-center">
      <div class="font-medium flex">
        <a
          :href="order.admin_url"
          target="_blank"
          rel="noopener noreferrer"
          class="hover:underline text-n-slate-12 cursor-pointer truncate"
        >
          {{
            $t('CONVERSATION_SIDEBAR.WOOCOMMERCE.ORDER_ID', { id: order.id })
          }}
          <i class="i-lucide-external-link pl-5" />
        </a>
      </div>
      <div class="text-xs px-2 py-1 rounded capitalize" :class="statusClass">
        {{ paymentStatus }}
      </div>
    </div>
    <div class="text-sm text-n-slate-12">
      <span class="text-n-slate-11 border-r border-n-weak pr-2">
        {{ formatDate(order.date_created) }}
      </span>
      <span class="text-n-slate-11 pl-2">
        {{ formatCurrency(order.total, order.currency) }}
      </span>
    </div>
  </div>
</template>
