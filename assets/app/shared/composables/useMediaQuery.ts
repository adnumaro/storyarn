import { onBeforeUnmount, onMounted, readonly, ref, type Ref } from "vue";

export function useMediaQuery(query: string): Readonly<Ref<boolean>> {
  const matches = ref(false);
  let mediaQueryList: MediaQueryList | null = null;

  function sync(event: MediaQueryList | MediaQueryListEvent): void {
    matches.value = event.matches;
  }

  onMounted(() => {
    mediaQueryList = window.matchMedia(query);
    sync(mediaQueryList);
    mediaQueryList.addEventListener("change", sync);
  });

  onBeforeUnmount(() => {
    mediaQueryList?.removeEventListener("change", sync);
  });

  return readonly(matches);
}
