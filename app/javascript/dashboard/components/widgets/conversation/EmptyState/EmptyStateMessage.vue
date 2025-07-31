<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';
import { mapGetters } from 'vuex';
export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
  },
};
</script>

<template>
  <div class="flex flex-col items-center justify-center h-full">
    <img
      class="m-4 w-32 hidden dark:block"
      :src="globalConfig.logoThumbnail"
      :alt="globalConfig.installationName"
    />
    <img
      class="m-4 w-32 block dark:hidden"
      :src="globalConfig.logoThumbnail"
      :alt="globalConfig.installationName"
    />
    <span class="text-sm text-n-slate-12 font-medium text-center">
      {{ message }}
      <br />
    </span>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
