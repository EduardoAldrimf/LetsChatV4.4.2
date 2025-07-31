<script>
export default {
  name: 'Avatar',
  props: {
    username: {
      type: String,
      default: '',
    },
    size: {
      type: Number,
      default: 40,
    },
  },
  computed: {
    style() {
      return {
        fontSize: `${Math.floor(this.size / 2.5)}px`,
      };
    },
    userInitial() {
      const parts = this.username.split(/[ -]/);
      let initials = parts.reduce((acc, curr) => acc + curr.charAt(0), '');

      if (initials.length > 2 && initials.search(/[A-Z]/) !== -1) {
        initials = initials.replace(/[a-z]+/g, '');
      }
      initials = initials.substring(0, 2).toUpperCase();

      return initials;
    },
  },
};
</script>

<template>
  <div class="avatar-container" :style="style" aria-hidden="true">
    <slot>{{ userInitial }}</slot>
  </div>
</template>

<style scoped>
@tailwind components;
@layer components {
  .avatar-color {
    background-image: linear-gradient(to top, #29a2a7 0%, #29a2a7 100%);
  }

  .dark-avatar-color {
    background-image: linear-gradient(to top, #29a2a7 0%, #29a2a7 100%);
  }
}
.avatar-container {
  @apply flex leading-[100%] font-medium items-center justify-center text-center cursor-default avatar-color dark:dark-avatar-color text-n-solid-1;
}
</style>
