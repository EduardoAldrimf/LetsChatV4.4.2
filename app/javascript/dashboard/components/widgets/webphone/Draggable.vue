<script setup>
import { ref, reactive, onMounted } from 'vue';

const props = defineProps({
  initialX: { type: Number, default: 0 },
  initialY: { type: Number, default: 0 },
});

const dragging = ref(false);
const offset = reactive({ x: 0, y: 0 });
const x = ref(0);
const y = ref(0);
const borderClass = ref('');
const draggable = ref(null);

function startDrag(event) {
  dragging.value = true;
  offset.x = event.clientX - x.value;
  offset.y = event.clientY - y.value;
  document.addEventListener('mousemove', onDrag);
  document.addEventListener('mouseup', stopDrag);
}

function onDrag(event) {
  if (!dragging.value) return;
  const newX = event.clientX - offset.x;
  const newY = event.clientY - offset.y;
  const bodyWidth = document.body.clientWidth;
  const bodyHeight = document.body.clientHeight;
  const elementWidth = draggable.value.clientWidth;
  const elementHeight = draggable.value.clientHeight;
  const isAtLeft = newX <= 0;
  const isAtRight = newX + elementWidth >= bodyWidth;
  const isAtTop = newY <= 0;
  const isAtBottom = newY + elementHeight >= bodyHeight;
  const borders = [];
  if (isAtLeft) borders.push('border-l border-red-500');
  if (isAtRight) borders.push('border-r border-red-500');
  if (isAtTop) borders.push('border-t border-red-500');
  if (isAtBottom) borders.push('border-b border-red-500');
  borderClass.value = borders.join(' ');
  x.value = Math.max(0, Math.min(newX, bodyWidth - elementWidth));
  y.value = Math.max(0, Math.min(newY, bodyHeight - elementHeight));
}

function stopDrag() {
  dragging.value = false;
  document.removeEventListener('mousemove', onDrag);
  document.removeEventListener('mouseup', stopDrag);
  localStorage.setItem(
    'draggablePosition',
    JSON.stringify({ x: x.value, y: y.value })
  );
}

onMounted(() => {
  const savedPosition = localStorage.getItem('draggablePosition');
  if (savedPosition) {
    const pos = JSON.parse(savedPosition);
    x.value = pos.x;
    y.value = pos.y;
  } else {
    x.value = props.initialX;
    y.value = props.initialY;
  }
});
</script>

<template>
  <div
    ref="draggable"
    class="absolute cursor-pointer rounded-xl z-40"
    :class="[borderClass]"
    :style="{ left: x + 'px', top: y + 'px' }"
    @mousedown="startDrag"
  >
    <slot />
  </div>
</template>
