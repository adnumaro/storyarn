<script setup>
import { ref } from "vue";
import { Button } from "./components/ui/button";
import { Input } from "./components/ui/input";
import { Switch } from "./components/ui/switch";
import { Badge } from "./components/ui/badge";
import {
	Select,
	SelectContent,
	SelectGroup,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "./components/ui/select";

const props = defineProps({
	message: { type: String, default: "LiveVue + shadcn-vue works!" },
});

const selectedFaction = ref("neutral");
const selectedTags = ref("fire");
const isPlayable = ref(false);
</script>

<template>
  <div class="space-y-8 p-8 max-w-lg mx-auto">
    <div class="p-4 rounded-lg bg-primary/10 text-primary font-medium">
      {{ message }}
    </div>

    <!-- Select -->
    <div class="space-y-2">
      <label class="text-sm font-medium">Select — Faction</label>
      <Select v-model="selectedFaction">
        <SelectTrigger>
          <SelectValue placeholder="Choose faction..." />
        </SelectTrigger>
        <SelectContent>
          <SelectGroup>
            <SelectItem value="forgemasters">Forgemasters</SelectItem>
            <SelectItem value="spiritbound">Spiritbound</SelectItem>
            <SelectItem value="conclave">Conclave</SelectItem>
            <SelectItem value="neutral">Neutral</SelectItem>
            <SelectItem value="independent">Independent</SelectItem>
          </SelectGroup>
        </SelectContent>
      </Select>
      <p class="text-xs text-muted-foreground">Selected: {{ selectedFaction }}</p>
    </div>

    <!-- Buttons -->
    <div class="space-y-2">
      <label class="text-sm font-medium">Button</label>
      <div class="flex gap-2">
        <Button>Primary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
        <Button variant="destructive">Danger</Button>
      </div>
    </div>

    <!-- Switch -->
    <div class="space-y-2">
      <label class="text-sm font-medium">Switch</label>
      <div class="flex items-center gap-3">
        <Switch v-model:checked="isPlayable" />
        <span class="text-sm">Playable Character: {{ isPlayable }}</span>
      </div>
    </div>

    <!-- Input -->
    <div class="space-y-2">
      <label class="text-sm font-medium">Input</label>
      <Input placeholder="Type something..." />
    </div>

    <!-- Badge -->
    <div class="space-y-2">
      <label class="text-sm font-medium">Badge</label>
      <div class="flex gap-2">
        <Badge>Active</Badge>
        <Badge variant="secondary">Draft</Badge>
        <Badge variant="outline">Archived</Badge>
        <Badge variant="destructive">Error</Badge>
      </div>
    </div>
  </div>
</template>
